// DiagnosticPage.ets - 数据获取诊断页面（升级版）

import { pasteboard } from '@kit.BasicServicesKit';
import http from '@ohos.net.http';
import {
  getCookies, getStudentId, isLoggedIn,
  fetchSemesters, fetchGrades, fetchCourseSchedule, fetchExams,
  fetchStudentInfo,
  getCachedStudentInfo, StudentInfo,
  JW_BASE, CAS_BASE
} from '../../service/NetworkService';
import { AppKeys } from '../Index';
import { Semester } from '../../model/Semester';

type LogLevel = 'INFO' | 'OK' | 'WARN' | 'ERR';
type TestStatus = 'idle' | 'running' | 'success' | 'error' | 'timeout' | 'warn';

interface LogEntry {
  time: string;
  level: LogLevel;
  msg: string;
}

interface TestResult {
  label: string;
  status: TestStatus;
  detail: string;
  duration: number;
}

interface UrlTestItem {
  url: string;
  name: string;
}

@Component
export struct DiagnosticPage {
  @State logs: LogEntry[] = [];
  @State isTesting: boolean = false;
  @State testResults: TestResult[] = [];
  @State overallStatus: string = '';
  @State overallColor: string = '#8E8E93';
  @StorageLink(AppKeys.USERNAME) username: string = '';
  @StorageLink(AppKeys.IS_LOGGED_IN) isLoggedIn_: boolean = false;
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @StorageLink(AppKeys.STUDENT_INFO) studentInfoStr: string = '';
  private scroller: Scroller = new Scroller();

  private now(): string {
    const d = new Date();
    const p2 = (n: number) => n.toString().padStart(2, '0');
    return `${p2(d.getHours())}:${p2(d.getMinutes())}:${p2(d.getSeconds())}`;
  }

  private log(level: LogLevel, msg: string): void {
    this.logs = [...this.logs, { time: this.now(), level, msg }];
    setTimeout(() => {
      try { this.scroller.scrollEdge(Edge.Bottom); } catch {}
    }, 50);
  }

  private clearLogs(): void {
    this.logs = [];
    this.testResults = [];
    this.overallStatus = '';
    this.overallColor = '#8E8E93';
  }

  private async copyLogs(): Promise<void> {
    if (this.logs.length === 0) return;
    const text = this.logs
      .map(e => `[${e.time}][${e.level}] ${e.msg}`)
      .join('\n');
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(pasteData);
      this.log('OK', '日志已复制到剪贴板');
    } catch (e) {
      this.log('ERR', `复制失败: ${(e as Error).message}`);
    }
  }

  private addTestResult(label: string, status: TestStatus, detail: string, duration: number = 0): void {
    const existing = this.testResults.findIndex(r => r.label === label);
    const result: TestResult = { label, status, detail, duration };
    if (existing >= 0) {
      this.testResults[existing] = result;
      this.testResults = [...this.testResults];
    } else {
      this.testResults = [...this.testResults, result];
    }
  }

  private getStatusIcon(status: TestStatus): string {
    switch (status) {
      case 'success': return '✓';
      case 'error': return '✕';
      case 'timeout': return '⏱';
      case 'running': return '⟳';
      default: return '○';
    }
  }

  private getStatusColor(status: TestStatus): string {
    switch (status) {
      case 'success': return '#34C759';
      case 'error': return '#FF3B30';
      case 'timeout': return '#FF9500';
      case 'warn': return '#FF9500';
      case 'running': return '#007AFF';
      default: return '#8E8E93';
    }
  }

  // ── 诊断：当前状态快照 ──
  private checkState(): void {
    this.clearLogs();
    this.log('INFO', '══ 当前状态快照 ══');
    this.log('INFO', `AppStorage.isLoggedIn = ${this.isLoggedIn_}`);
    this.log('INFO', `AppStorage.username   = "${this.username}"`);
    this.log('INFO', `NetworkService.isLoggedIn() = ${isLoggedIn()}`);

    const sid = getStudentId();
    this.log(sid.length > 0 ? 'OK' : 'WARN',
      `NetworkService.getStudentId() = "${sid.length > 0 ? sid : '(空！登录后才填充)'}"`);

    const cookies = getCookies();
    if (cookies.length === 0) {
      this.log('ERR', 'Cookies: (空！未登录或未恢复)');
      this.addTestResult('登录状态', 'error', '未获取到 Cookie', 0);
    } else {
      this.log('OK', `Cookies 长度: ${cookies.length} 字节`);
      const hasJSession = cookies.includes('JSESSIONID');
      const hasRoute = cookies.includes('route');
      const hasCas = cookies.includes('iPlanetDirectoryPro');
      this.log(hasJSession ? 'OK' : 'WARN', `  JSESSIONID: ${hasJSession ? '存在' : '缺失'}`);
      this.log(hasRoute ? 'OK' : 'WARN',    `  route: ${hasRoute ? '存在' : '缺失'}`);
      this.log(hasCas ? 'OK' : 'INFO',      `  iPlanetDirectoryPro: ${hasCas ? '存在' : '无(正常)'}`);

      // 判断登录方式
      if (hasCas) {
        this.log('INFO', '  登录方式: 网页统一认证 (Cookie 完整)');
        this.addTestResult('登录状态', 'success', '网页统一认证登录', 0);
      } else if (hasJSession && !hasRoute) {
        this.log('WARN', '  登录方式: 账号密码登录 (缺少 route Cookie)');
        this.addTestResult('登录状态', 'warn', '账号密码登录，缺少 route', 0);
      } else if (hasJSession && hasRoute) {
        this.log('OK', '  登录方式: 账号密码登录 (Cookie 完整)');
        this.addTestResult('登录状态', 'success', '账号密码登录，Cookie 完整', 0);
      }

      for (const pair of cookies.split(';')) {
        const trimmed = pair.trim();
        if (trimmed.length > 0) {
          this.log('INFO', `  cookie-pair: ${trimmed.substring(0, 120)}`);
        }
      }
    }

    // 学生信息
    const cachedInfo = getCachedStudentInfo();
    let parsedInfo: StudentInfo | null = null;
    if (this.studentInfoStr.length > 0) {
      try {
        parsedInfo = JSON.parse(this.studentInfoStr) as StudentInfo;
      } catch (e) {
        parsedInfo = null;
      }
    }
    const info = parsedInfo ?? cachedInfo;
    if (info && info.name.length > 0) {
      this.log('OK', `学生信息: ${info.name} (${info.studentId}) ${info.college}`);
      this.addTestResult('学生信息', 'success', `${info.name} ${info.college}`, 0);
    } else if (sid.length > 0) {
      this.log('WARN', `学生信息: 学号 ${sid}，姓名未获取`);
      this.addTestResult('学生信息', 'warn', `学号 ${sid}，姓名未获取`, 0);
    } else {
      this.addTestResult('学生信息', 'idle', '未登录', 0);
    }

    const semCount = (this.semesters ?? []).length;
    this.log(semCount > 0 ? 'OK' : 'WARN',
      `AppStorage.semesters = ${semCount} 个学期`);
    if (semCount > 0) {
      const last = (this.semesters ?? [])[semCount - 1];
      this.log('INFO',
        `  最新: ${last.id} (${last.name}), ` +
        `课程数=${last.courses?.length ?? 0}, ` +
        `考试数=${last.exams?.length ?? 0}`);
      this.addTestResult('学期数据', 'success', `${semCount} 个学期`, 0);
    } else {
      this.addTestResult('学期数据', 'idle', '无数据', 0);
    }
  }

  // ── 测试：基础网络连通性 ──
  private async testConnectivity(): Promise<void> {
    this.log('INFO', '── 测试: 基础网络连通性 ──');
    const urls: UrlTestItem[] = [
      { url: 'https://www.baidu.com', name: '公网 (百度)' },
      { url: 'https://developer.huawei.com/consumer/cn/', name: '公网 (华为)' },
      { url: `${JW_BASE}/jwglxt`, name: '校内 (教务系统)' },
      { url: `${CAS_BASE}/login`, name: '校内 (CAS认证)' }
    ];

    let allOk = true;
    for (const item of urls) {
      this.addTestResult(item.name, 'running', '测试中...', 0);
      const req = http.createHttp();
      try {
        const start = Date.now();
        const resp = await req.request(item.url, {
          method: http.RequestMethod.GET,
          header: { 'Connection': 'close' },
          connectTimeout: 10000,
          readTimeout: 10000,
          dnsServers: ['114.114.114.114', '223.5.5.5', '8.8.8.8']
        });
        const cost = Date.now() - start;
        if (resp.responseCode === 200) {
          this.log('OK', `${item.name}: HTTP ${resp.responseCode}, ${cost}ms`);
          this.addTestResult(item.name, 'success', `${cost}ms`, cost);
        } else {
          this.log('WARN', `${item.name}: HTTP ${resp.responseCode}, ${cost}ms`);
          this.addTestResult(item.name, 'warn', `HTTP ${resp.responseCode}`, cost);
          if (item.name.includes('校内')) allOk = false;
        }
      } catch (e) {
        const msg = (e as Error).message;
        this.log('ERR', `${item.name}: ${msg}`);
        this.addTestResult(item.name, msg.includes('timeout') ? 'timeout' : 'error', msg, 0);
        if (item.name.includes('校内')) allOk = false;
      } finally {
        req.destroy();
      }
    }

    if (allOk) {
      this.addTestResult('网络连通性', 'success', '全部正常', 0);
    } else {
      this.addTestResult('网络连通性', 'warn', '校内网络可能受限', 0);
    }
  }

  // ── 测试：获取学生信息 ──
  private async testStudentInfo(): Promise<void> {
    this.log('INFO', '── 测试: 获取学生信息 ──');
    this.addTestResult('学生信息获取', 'running', '测试中...', 0);
    try {
      const start = Date.now();
      const r = await fetchStudentInfo();
      const cost = Date.now() - start;
      if (r.success) {
        this.log('OK', `学号: ${r.studentId}, 姓名: ${r.name || '(未获取)'}, 学院: ${r.college || '(未获取)'}`);
        if (r.name.length > 0) {
          this.addTestResult('学生信息获取', 'success', `${r.name} ${cost}ms`, cost);
        } else {
          this.addTestResult('学生信息获取', 'warn', `学号 ${r.studentId}，姓名未获取`, cost);
        }
      } else {
        this.log('ERR', `失败: 所有方法均无法提取学号`);
        this.addTestResult('学生信息获取', 'error', '无法提取学号', cost);
      }
    } catch (e) {
      const msg = (e as Error).message;
      this.log('ERR', `异常: ${msg}`);
      this.addTestResult('学生信息获取', 'error', msg, 0);
    }
  }

  // ── 测试：获取学期列表 ──
  private async testSemesters(): Promise<void> {
    this.log('INFO', '── 测试: 获取学期列表 ──');
    this.addTestResult('学期列表', 'running', '测试中...', 0);
    try {
      const start = Date.now();
      const r = await fetchSemesters();
      const cost = Date.now() - start;
      this.log(r.success ? 'OK' : 'ERR', `fetchSemesters success=${r.success}, msg="${r.message}"`);
      if (r.success && r.data) {
        this.log(r.data.length > 0 ? 'OK' : 'WARN', `获取到 ${r.data.length} 个学期`);
        for (const s of r.data) {
          this.log('INFO', `  ${s.id} → ${s.name}`);
        }
        this.addTestResult('学期列表', r.data.length > 0 ? 'success' : 'warn', `${r.data.length} 个学期 ${cost}ms`, cost);
      } else {
        this.addTestResult('学期列表', 'error', r.message || '失败', cost);
      }
    } catch (e) {
      const msg = (e as Error).message;
      this.log('ERR', `异常: ${msg}`);
      this.addTestResult('学期列表', 'error', msg, 0);
    }
  }

  // ── 测试：获取成绩 ──
  private async testGrades(): Promise<void> {
    this.log('INFO', '── 测试: 获取成绩 ──');
    this.addTestResult('成绩查询', 'running', '测试中...', 0);
    const sems = this.semesters ?? [];
    const semId = sems.length > 0 ? sems[sems.length - 1].id : '2024-2025-1';
    this.log('INFO', `使用学期 ID: ${semId}`);
    try {
      const start = Date.now();
      const r = await fetchGrades(semId);
      const cost = Date.now() - start;
      this.log(r.success ? 'OK' : 'ERR', `success=${r.success}, msg="${r.message}"`);
      if (r.success && r.data) {
        this.log(r.data.length > 0 ? 'OK' : 'INFO', `获取到 ${r.data.length} 条成绩记录`);
        for (let i = 0; i < Math.min(3, r.data.length); i++) {
          const c = r.data[i];
          this.log('INFO', `  [${i}] ${c.name} | 成绩:${c.grade} 绩点:${c.gradePoint}`);
        }
        this.addTestResult('成绩查询', 'success', `${r.data.length} 条记录 ${cost}ms`, cost);
      } else {
        this.addTestResult('成绩查询', 'error', r.message || '失败', cost);
      }
    } catch (e) {
      const msg = (e as Error).message;
      this.log('ERR', `异常: ${msg}`);
      this.addTestResult('成绩查询', 'error', msg, 0);
    }
  }

  // ── 测试：获取课表 ──
  private async testSchedule(): Promise<void> {
    this.log('INFO', '── 测试: 获取课表 ──');
    this.addTestResult('课表查询', 'running', '测试中...', 0);
    const sems = this.semesters ?? [];
    const semId = sems.length > 0 ? sems[sems.length - 1].id : '2024-2025-1';
    this.log('INFO', `使用学期 ID: ${semId}`);
    try {
      const start = Date.now();
      const r = await fetchCourseSchedule(semId);
      const cost = Date.now() - start;
      this.log(r.success ? 'OK' : 'ERR', `success=${r.success}, msg="${r.message}"`);
      if (r.success && r.data) {
        this.log(r.data.length > 0 ? 'OK' : 'INFO', `获取到 ${r.data.length} 门课程`);
        for (let i = 0; i < Math.min(3, r.data.length); i++) {
          const c = r.data[i];
          this.log('INFO', `  [${i}] ${c.name} | 教师:${c.teacher} 时间段:${c.timeSlots?.length ?? 0}个`);
        }
        this.addTestResult('课表查询', 'success', `${r.data.length} 门课程 ${cost}ms`, cost);
      } else {
        this.addTestResult('课表查询', 'error', r.message || '失败', cost);
      }
    } catch (e) {
      const msg = (e as Error).message;
      this.log('ERR', `异常: ${msg}`);
      this.addTestResult('课表查询', 'error', msg, 0);
    }
  }

  // ── 测试：获取考试 ──
  private async testExams(): Promise<void> {
    this.log('INFO', '── 测试: 获取考试 ──');
    this.addTestResult('考试查询', 'running', '测试中...', 0);
    const sems = this.semesters ?? [];
    const semId = sems.length > 0 ? sems[sems.length - 1].id : '2024-2025-1';
    this.log('INFO', `使用学期 ID: ${semId}`);
    try {
      const start = Date.now();
      const r = await fetchExams(semId);
      const cost = Date.now() - start;
      this.log(r.success ? 'OK' : 'ERR', `success=${r.success}, msg="${r.message}"`);
      if (r.success && r.data) {
        this.log('OK', `获取到 ${r.data.length} 条考试记录`);
        for (let i = 0; i < Math.min(3, r.data.length); i++) {
          const e = r.data[i];
          this.log('INFO', `  [${i}] ${e.courseName} | 地点:${e.location} 座位:${e.seatNo}`);
        }
        this.addTestResult('考试查询', 'success', `${r.data.length} 条记录 ${cost}ms`, cost);
      } else {
        this.addTestResult('考试查询', 'error', r.message || '失败', cost);
      }
    } catch (e) {
      const msg = (e as Error).message;
      this.log('ERR', `异常: ${msg}`);
      this.addTestResult('考试查询', 'error', msg, 0);
    }
  }

  private async withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T | undefined> {
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.log('ERR', `${label} 超时（>${ms}ms）`);
        resolve(undefined);
      }, ms);
      promise.then((v) => { clearTimeout(timer); resolve(v); }).catch(() => { clearTimeout(timer); resolve(undefined); });
    });
  }

  // ── 全量测试 ──
  private async runFullTest(): Promise<void> {
    if (this.isTesting) return;
    this.isTesting = true;
    this.clearLogs();
    this.log('INFO', '▶ 开始全量诊断...');

    this.checkState();

    if (!isLoggedIn()) {
      this.log('ERR', '未登录，跳过 API 测试。请先登录后重试。');
      this.overallStatus = '未登录';
      this.overallColor = '#FF3B30';
      this.isTesting = false;
      return;
    }

    // 串行执行网络连通性测试（避免并行影响准确性）
    await this.testConnectivity();

    // 并行执行 API 测试
    await Promise.all([
      this.withTimeout(this.testStudentInfo(), 15000, '学生信息'),
      this.withTimeout(this.testSemesters(), 15000, '学期列表'),
      this.withTimeout(this.testGrades(), 15000, '成绩'),
      this.withTimeout(this.testSchedule(), 15000, '课表'),
      this.withTimeout(this.testExams(), 15000, '考试')
    ]);

    // 计算总体状态
    const errors = this.testResults.filter(r => r.status === 'error' || r.status === 'timeout').length;
    const warns = this.testResults.filter(r => r.status === 'warn').length;
    if (errors > 0) {
      this.overallStatus = `${errors} 项异常，建议检查网络或重新登录`;
      this.overallColor = '#FF3B30';
    } else if (warns > 0) {
      this.overallStatus = `${warns} 项警告，部分功能可能受限`;
      this.overallColor = '#FF9500';
    } else {
      this.overallStatus = '所有测试通过';
      this.overallColor = '#34C759';
    }

    this.log('INFO', '▶ 全量诊断完成');
    this.isTesting = false;
  }

  @Builder
  StatusCard() {
    Column({ space: 8 }) {
      // 总体状态
      Row({ space: 8 }) {
        Text(this.overallStatus.length > 0 ? this.overallStatus : '点击「全量诊断」开始测试')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.overallStatus.length > 0 ? this.overallColor : $r('app.color.text_secondary'))
        if (this.isTesting) {
          LoadingProgress().width(16).height(16).color($r('app.color.color_blue'))
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // 测试结果网格
      if (this.testResults.length > 0) {
        Grid() {
          ForEach(this.testResults, (result: TestResult) => {
            GridItem() {
              Column({ space: 4 }) {
                Text(this.getStatusIcon(result.status))
                  .fontSize(18)
                  .fontColor(this.getStatusColor(result.status))
                Text(result.label)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                if (result.detail.length > 0 && result.status !== 'idle') {
                  Text(result.detail)
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .padding(8)
              .width('100%')
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(10)
            }
          }, (result: TestResult, idx: number) => `${idx}_${result.label}`)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }

  @Builder
  LogItem(entry: LogEntry) {
    Row({ space: 6 }) {
      Text(entry.time)
        .fontSize(10)
        .fontColor('#8E8E93')
        .width(52)
        .flexShrink(0)

      Text(entry.level)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(entry.level === 'OK' ? '#34C759' :
          entry.level === 'ERR' ? '#FF3B30' :
          entry.level === 'WARN' ? '#FF9500' : '#007AFF')
        .width(32)
        .flexShrink(0)

      Text(entry.msg)
        .fontSize(11)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .wordBreak(WordBreak.BREAK_ALL)
    }
    .width('100%')
    .padding({ top: 3, bottom: 3, left: 12, right: 12 })
    .alignItems(VerticalAlign.Top)
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column({ space: 12 }) {
            // ── 状态概览卡片 ──
            this.StatusCard()

            // ── 操作按钮 ──
            Row({ space: 10 }) {
              Button('全量诊断')
                .onClick(() => { this.runFullTest(); })
                .enabled(!this.isTesting)
                .fontSize(14).height(40)
                .backgroundColor($r('app.color.color_blue'))
                .fontColor(Color.White)
                .borderRadius(10)
                .padding({ left: 20, right: 20 })
                .layoutWeight(1)

              Button('状态快照')
                .onClick(() => { this.checkState(); })
                .enabled(!this.isTesting)
                .fontSize(14).height(40)
                .backgroundColor($r('app.color.card_background'))
                .fontColor($r('app.color.text_primary'))
                .borderRadius(10)
                .padding({ left: 16, right: 16 })

              Button('清空')
                .onClick(() => { this.clearLogs(); })
                .enabled(!this.isTesting)
                .fontSize(14).height(40)
                .backgroundColor($r('app.color.card_background'))
                .fontColor($r('app.color.color_red'))
                .borderRadius(10)
                .padding({ left: 16, right: 16 })
            }
            .width('100%')
            .padding({ left: 16, right: 16 })

            // ── 单项测试按钮 ──
            Row({ space: 8 }) {
              this.QuickTestBtn('学期', () => this.testSemesters())
              this.QuickTestBtn('成绩', () => this.testGrades())
              this.QuickTestBtn('课表', () => this.testSchedule())
              this.QuickTestBtn('考试', () => this.testExams())
              this.QuickTestBtn('学号', () => this.testStudentInfo())
              this.QuickTestBtn('网络', () => this.testConnectivity())
            }
            .width('100%')
            .padding({ left: 16, right: 16 })

            // ── 日志区域 ──
            if (this.logs.length > 0) {
              Column({ space: 6 }) {
                Row() {
                  Text('详细日志')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(`${this.logs.length} 条`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_tertiary'))
                  Button({ type: ButtonType.Circle }) {
                    Text('📋').fontSize(12)
                  }
                  .width(28).height(28)
                  .backgroundColor($r('app.color.progress_bg'))
                  .margin({ left: 8 })
                  .onClick(() => this.copyLogs())
                }
                .width('100%')

                Scroll(this.scroller) {
                  Column() {
                    ForEach(this.logs, (entry: LogEntry, idx: number) => {
                      this.LogItem(entry)
                      if (idx < this.logs.length - 1) {
                        Row().width('100%').height(0.5)
                          .backgroundColor($r('app.color.separator'))
                          .margin({ left: 12 })
                      }
                    }, (entry: LogEntry, idx: number) => `${idx}_${entry.time}_${entry.msg}`)
                  }
                  .width('100%')
                  .padding({ bottom: 20 })
                }
                .height(280)
                .scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(16)
            }

            Blank().height(40)
          }
          .width('100%')
          .padding({ top: 4, bottom: 16 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.app_background'))
    }
    .title('数据诊断')
    .onReady((_ctx: NavDestinationContext) => {
    })
  }

  @Builder
  QuickTestBtn(label: string, onTap: () => Promise<void>) {
    Button(label)
      .fontSize(12).height(32)
      .backgroundColor($r('app.color.card_background'))
      .fontColor($r('app.color.text_primary'))
      .borderRadius(8).padding({ left: 10, right: 10 })
      .enabled(!this.isTesting)
      .onClick(async () => {
        this.isTesting = true;
        await onTap();
        this.isTesting = false;
      })
  }
}

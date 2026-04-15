// DiagnosticPage.ets - 数据获取诊断页面（调试用）

import { pasteboard } from '@kit.BasicServicesKit';
import http from '@ohos.net.http';
import {
  getCookies, getStudentId, isLoggedIn,
  fetchSemesters, fetchGrades, fetchCourseSchedule, fetchExams,
  fetchStudentInfo, fetchRaw, fetchRawGet,
  JW_BASE
} from '../../service/NetworkService';
import { AppKeys } from '../Index';
import { Semester } from '../../model/Semester';

type LogLevel = 'INFO' | 'OK' | 'WARN' | 'ERR';

interface LogEntry {
  time: string;
  level: LogLevel;
  msg: string;
}

@Component
export struct DiagnosticPage {
  private pathStack: NavPathStack = new NavPathStack();
  @State logs: LogEntry[] = [];
  @State isTesting: boolean = false;
  @StorageLink(AppKeys.USERNAME) username: string = '';
  @StorageLink(AppKeys.IS_LOGGED_IN) isLoggedIn_: boolean = false;
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  private scroller: Scroller = new Scroller();

  private now(): string {
    const d = new Date();
    const p2 = (n: number) => n.toString().padStart(2, '0');
    return `${p2(d.getHours())}:${p2(d.getMinutes())}:${p2(d.getSeconds())}`;
  }

  private log(level: LogLevel, msg: string): void {
    this.logs = [...this.logs, { time: this.now(), level, msg }];
    // 滚动到底部
    setTimeout(() => {
      try { this.scroller.scrollEdge(Edge.Bottom); } catch {}
    }, 50);
  }

  private clearLogs(): void {
    this.logs = [];
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
    } else {
      this.log('OK', `Cookies 长度: ${cookies.length} 字节`);
      const hasJSession = cookies.includes('JSESSIONID');
      const hasRoute = cookies.includes('route');
      const hasCas = cookies.includes('iPlanetDirectoryPro');
      this.log(hasJSession ? 'OK' : 'WARN', `  JSESSIONID: ${hasJSession ? '存在' : '缺失'}`);
      this.log(hasRoute ? 'OK' : 'WARN',    `  route: ${hasRoute ? '存在' : '缺失'}`);
      this.log(hasCas ? 'OK' : 'INFO',      `  iPlanetDirectoryPro: ${hasCas ? '存在' : '无(正常)'}`);
      for (const pair of cookies.split(';')) {
        const trimmed = pair.trim();
        if (trimmed.length > 0) {
          this.log('INFO', `  cookie-pair: ${trimmed.substring(0, 120)}`);
        }
      }
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
      const parts = last.id.split('-');
      if (parts.length >= 3) {
        const year = `${parts[0]}-${parts[1]}`;
        const term = parts[2] === '1' ? '3' : '12';
        this.log('INFO', `  转换: xnm=${year}, xqm=${term}`);
      }
    }
  }

  // ── 测试：基础网络连通性 ──
  private async testConnectivity(): Promise<void> {
    this.log('INFO', '── 测试: 基础网络连通性 ──');
    const urls = [
      'https://www.baidu.com',
      'https://developer.huawei.com/consumer/cn/',
      'https://zdbk.zju.edu.cn/jwglxt',
      'https://zjuam.zju.edu.cn/cas/login'
    ];
    for (const url of urls) {
      const req = http.createHttp();
      try {
        const start = Date.now();
        const resp = await req.request(url, {
          method: http.RequestMethod.GET,
          header: { 'Connection': 'close' },
          connectTimeout: 10000,
          readTimeout: 10000
        });
        const cost = Date.now() - start;
        this.log(resp.responseCode === 200 ? 'OK' : 'WARN',
          `连通性 ${url}: HTTP ${resp.responseCode}, ${cost}ms, resultLen=${(resp.result as string)?.length ?? 0}`);
        if (resp.responseCode !== 200) {
          const preview = (resp.result as string ?? '').substring(0, 120);
          this.log('INFO', `  响应预览: ${preview}`);
        }
      } catch (e) {
        this.log('ERR', `连通性 ${url}: 异常 - ${(e as Error).message}`);
      } finally {
        req.destroy();
      }
    }
  }

  // ── 测试：获取学生信息 ──
  private async testStudentInfo(): Promise<void> {
    this.log('INFO', '── 测试: 获取学生信息 ──');
    try {
      const r = await fetchStudentInfo();
      if (r.success) {
        this.log('OK', `学号: ${r.studentId}, 姓名: ${r.name || '(未获取)'}`);
      } else {
        this.log('ERR', `失败: 所有方法均无法提取学号`);
      }
    } catch (e) {
      this.log('ERR', `异常: ${(e as Error).message}`);
    }
  }

  // ── 测试：获取学期列表 ──
  private async testSemesters(): Promise<void> {
    this.log('INFO', '── 测试: 获取学期列表 ──');
    try {
      // 使用 GET 获取原始 HTML 供调试（学期页面是 GET 接口）
      const rawR = await fetchRawGet(
        `${JW_BASE}/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default`);
      this.log(rawR.success ? 'INFO' : 'ERR',
        `原始响应 (${rawR.message}): ${(rawR.data ?? '').substring(0, 200)}`);
      if (!rawR.success) {
        this.log('WARN', '原始 GET 请求失败，尝试使用底层 http 模块直接请求...');
        const req = http.createHttp();
        try {
          const direct = await req.request(`${JW_BASE}/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default`, {
            method: http.RequestMethod.GET,
            connectTimeout: 10000,
            readTimeout: 10000,
            usingCache: false
          });
          req.destroy();
          this.log('INFO', `底层直接请求 HTTP ${direct.responseCode}, length=${(direct.result as string)?.length ?? 0}`);
        } catch (e2) {
          req.destroy();
          this.log('ERR', `底层直接请求也失败: ${(e2 as Error).message}`);
        }
      }

      const r = await fetchSemesters();
      this.log(r.success ? 'OK' : 'ERR', `fetchSemesters success=${r.success}, msg="${r.message}"`);
      if (r.success && r.data) {
        this.log(r.data.length > 0 ? 'OK' : 'WARN', `获取到 ${r.data.length} 个学期`);
        for (const s of r.data) {
          this.log('INFO', `  ${s.id} → ${s.name}`);
        }
        if (r.data.length === 0) {
          this.log('WARN', '  检查上方原始响应中是否含有 name="xnm" 和 name="xqm" 的 select 元素');
        }
      }
    } catch (e) {
      this.log('ERR', `异常: ${(e as Error).message}`);
    }
  }

  // ── 测试：获取成绩（用最新学期） ──
  private async testGrades(): Promise<void> {
    this.log('INFO', '── 测试: 获取成绩 ──');
    const sems = this.semesters ?? [];
    const semId = sems.length > 0 ? sems[sems.length - 1].id : '2024-2025-1';
    this.log('INFO', `使用学期 ID: ${semId}`);
    try {
      const r = await fetchGrades(semId);
      this.log(r.success ? 'OK' : 'ERR', `success=${r.success}, msg="${r.message}"`);
      if (r.success && r.data) {
        this.log(r.data.length > 0 ? 'OK' : 'WARN', `获取到 ${r.data.length} 条成绩记录`);
        for (let i = 0; i < Math.min(3, r.data.length); i++) {
          const c = r.data[i];
          this.log('INFO', `  [${i}] ${c.name} | 成绩:${c.grade} 绩点:${c.gradePoint}`);
        }
        if (r.data.length === 0) {
          // 获取原始响应帮助诊断
          const parts = semId.split('-');
          const year = parts.length >= 2 ? `${parts[0]}-${parts[1]}` : '2024-2025';
          const term = parts.length >= 3 ? (parts[2] === '1' ? '3' : '12') : '3';
          const rawR = await fetchRaw(
            `${JW_BASE}/cxdy/xscjcx_cxXscjIndex.html?doType=query&queryModel.showCount=5000`,
            `xnm=${year}&xqm=${term}&_search=false&nd=1&queryModel.showCount=5000&queryModel.currentPage=1&queryModel.sortName=&queryModel.sortOrder=asc&time=0`,
            { 'Referer': `${JW_BASE}/cxdy/xscjcx_cxXscjIndex.html` }
          );
          this.log('INFO', `  成绩原始响应 (${rawR.message}): ${(rawR.data ?? '').substring(0, 300)}`);
        }
      }
    } catch (e) {
      this.log('ERR', `异常: ${(e as Error).message}`);
    }
  }

  // ── 测试：获取课表（用最新学期） ──
  private async testSchedule(): Promise<void> {
    this.log('INFO', '── 测试: 获取课表 ──');
    const sems = this.semesters ?? [];
    const semId = sems.length > 0 ? sems[sems.length - 1].id : '2024-2025-1';
    this.log('INFO', `使用学期 ID: ${semId}`);
    try {
      const r = await fetchCourseSchedule(semId);
      this.log(r.success ? 'OK' : 'ERR', `success=${r.success}, msg="${r.message}"`);
      if (!r.success) {
        // 获取原始响应帮助诊断 901 等错误
        const parts = semId.split('-');
        const year = parts.length >= 2 ? `${parts[0]}-${parts[1]}` : '2024-2025';
        const term = parts.length >= 3 ? (parts[2] === '1' ? '3' : '12') : '3';
        const rawR = await fetchRaw(
          `${JW_BASE}/kbcx/xskbcx_cxXsKb.html`,
          `xnm=${year}&xqm=${term}&captcha_value=`,
          { 'X-Requested-With': 'XMLHttpRequest', 'Referer': `${JW_BASE}/kbcx/xskbcx_cxXskbcxIndex.html` }
        );
        this.log('INFO', `  课表原始响应 (${rawR.message}): ${(rawR.data ?? '').substring(0, 300)}`);
      }
      if (r.success && r.data) {
        this.log(r.data.length > 0 ? 'OK' : 'WARN', `获取到 ${r.data.length} 门课程`);
        for (let i = 0; i < Math.min(3, r.data.length); i++) {
          const c = r.data[i];
          this.log('INFO', `  [${i}] ${c.name} | 教师:${c.teacher} 时间段:${c.timeSlots?.length ?? 0}个`);
        }
        if (r.data.length === 0) {
          this.log('WARN', '  课表为空：检查 kcb 字段 HTML 格式是否与正则匹配');
        }
        // 检查学号是否被提取
        const sid = getStudentId();
        if (sid.length > 0) {
          this.log('OK', `  从课表响应中提取到学号: ${sid}`);
        }
      }
    } catch (e) {
      this.log('ERR', `异常: ${(e as Error).message}`);
    }
  }

  // ── 测试：获取考试（用最新学期） ──
  private async testExams(): Promise<void> {
    this.log('INFO', '── 测试: 获取考试 ──');
    const sems = this.semesters ?? [];
    const semId = sems.length > 0 ? sems[sems.length - 1].id : '2024-2025-1';
    this.log('INFO', `使用学期 ID: ${semId}`);
    try {
      const r = await fetchExams(semId);
      this.log(r.success ? 'OK' : 'ERR', `success=${r.success}, msg="${r.message}"`);
      if (r.success && r.data) {
        this.log('OK', `获取到 ${r.data.length} 条考试记录`);
        for (let i = 0; i < Math.min(3, r.data.length); i++) {
          const e = r.data[i];
          this.log('INFO', `  [${i}] ${e.courseName} | 地点:${e.location} 座位:${e.seatNo}`);
        }
      }
    } catch (e) {
      this.log('ERR', `异常: ${(e as Error).message}`);
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
      this.isTesting = false;
      return;
    }

    // 并行执行，每项最多 15 秒，避免串行等待
    await Promise.all([
      this.withTimeout(this.testConnectivity(), 15000, '连通性'),
      this.withTimeout(this.testStudentInfo(), 15000, '学生信息'),
      this.withTimeout(this.testSemesters(), 15000, '学期列表'),
      this.withTimeout(this.testGrades(), 15000, '成绩'),
      this.withTimeout(this.testSchedule(), 15000, '课表'),
      this.withTimeout(this.testExams(), 15000, '考试')
    ]);

    this.log('INFO', '▶ 全量诊断完成');
    this.isTesting = false;
  }

  @Builder
  LogItem(entry: LogEntry) {
    Row({ space: 6 }) {
      Text(entry.time)
        .fontSize(10)
        .fontColor('#8E8E93')
        .width(56)
        .flexShrink(0)

      Text(entry.level)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(entry.level === 'OK' ? '#34C759' :
          entry.level === 'ERR' ? '#FF3B30' :
          entry.level === 'WARN' ? '#FF9500' : '#007AFF')
        .width(36)
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
        // ── 工具栏 ──
        Row({ space: 8 }) {
          Button('全量诊断') 
          .onClick(() => { this.runFullTest(); })
          .enabled(!this.isTesting)
          .fontSize(13).height(36)
          .backgroundColor($r('app.color.color_blue'))
          .fontColor(Color.White)
          .borderRadius(10)
          .padding({ left: 14, right: 14 })
          .layoutWeight(1)

          Button('状态快照') 
          .onClick(() => { this.checkState(); })
          .enabled(!this.isTesting)
          .fontSize(13).height(36)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(10)
          .padding({ left: 14, right: 14 })

          Button('清空') 
          .onClick(() => { this.clearLogs(); })
          .fontSize(13).height(36)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.color_red'))
          .borderRadius(10)
          .padding({ left: 14, right: 14 })

          Button('复制') 
          .onClick(() => { this.copyLogs(); })
          .enabled(this.logs.length > 0)
          .fontSize(13).height(36)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.color_blue'))
          .borderRadius(10)
          .padding({ left: 14, right: 14 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        // ── 单项测试按钮 ──
        Row({ space: 8 }) {
          Button('学期').fontSize(12).height(30)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(8).padding({ left: 10, right: 10 })
            .enabled(!this.isTesting)
            .onClick(async () => {
              this.isTesting = true;
              await this.testSemesters();
              this.isTesting = false;
            })
          Button('成绩').fontSize(12).height(30)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(8).padding({ left: 10, right: 10 })
            .enabled(!this.isTesting)
            .onClick(async () => {
              this.isTesting = true;
              await this.testGrades();
              this.isTesting = false;
            })
          Button('课表').fontSize(12).height(30)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(8).padding({ left: 10, right: 10 })
            .enabled(!this.isTesting)
            .onClick(async () => {
              this.isTesting = true;
              await this.testSchedule();
              this.isTesting = false;
            })
          Button('考试').fontSize(12).height(30)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(8).padding({ left: 10, right: 10 })
            .enabled(!this.isTesting)
            .onClick(async () => {
              this.isTesting = true;
              await this.testExams();
              this.isTesting = false;
            })
          Button('学号').fontSize(12).height(30)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(8).padding({ left: 10, right: 10 })
            .enabled(!this.isTesting)
            .onClick(async () => {
              this.isTesting = true;
              await this.testStudentInfo();
              this.isTesting = false;
            })
          Button('网络').fontSize(12).height(30)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(8).padding({ left: 10, right: 10 })
            .enabled(!this.isTesting)
            .onClick(async () => {
              this.isTesting = true;
              await this.testConnectivity();
              this.isTesting = false;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        if (this.isTesting) {
          Row({ space: 8 }) {
            LoadingProgress().width(16).height(16).color($r('app.color.color_blue'))
            Text('测试中...').fontSize(12).fontColor($r('app.color.text_secondary'))
          }
          .padding({ left: 16, bottom: 6 })
          .width('100%')
        }

        // ── 日志区域 ──
        if (this.logs.length === 0) {
          Column({ space: 8 }) {
            Text('点击「全量诊断」开始测试')
              .fontSize(14).fontColor($r('app.color.text_secondary'))
            Text('或点击上方单项按钮单独测试某个接口')
              .fontSize(12).fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
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
            .padding({ bottom: 40 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .margin({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.app_background'))
    }
    .title('数据诊断')
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }
}

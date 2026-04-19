// ScholarPage.ets - 学业信息主页

import http from '@ohos.net.http';
import { Semester, GpaInfo } from '../../model/Semester';
import { Todo, Course } from '../../model/Course';
import { AppKeys } from '../Index';
import { TwoLineCard, RoundRectangleCardWithForehead, SearchBar, EmptyView, LoadingView } from '../../components/CommonComponents';
import { fetchSemesters, fetchGrades, fetchCourseSchedule, fetchExams, fetchTodos, fetchStudentInfo, getCachedStudentInfo, StudentInfo, setCachedStudentInfo, JW_BASE } from '../../service/NetworkService';
import { StorageService } from '../../service/StorageService';
import common from '@ohos.app.ability.common';

interface SemesterIdParam {
  semesterId: string;
}

interface CourseScheduleParam {
  semesterId: string;
  isFirstHalf: boolean;
}

interface GradeDetailNavParam {
  semesterIndex: number;
}

@Component
export struct ScholarPage {
  navStack: NavPathStack = new NavPathStack();
  @StorageLink(AppKeys.SEMESTERS) @Watch('onSemestersChanged') semesters: Semester[] = [];
  @StorageLink(AppKeys.IS_GRS) isGrs: boolean = false;
  @StorageLink(AppKeys.HIDE_GPA) hideGpa: boolean = false;
  @StorageLink(AppKeys.IS_LOGGED_IN) @Watch('onLoginStateChanged') isLoggedIn: boolean = false;
  @StorageLink(AppKeys.LAST_UPDATE) lastUpdate: number = 0;
  @StorageLink(AppKeys.STUDENT_INFO) studentInfoStr: string = '';
  @StorageLink(AppKeys.USERNAME) username: string = '';
  @StorageLink(AppKeys.CURRENT_SEMESTER_INDEX) semesterIndex: number = 0;
  @State isRefreshing: boolean = false;
  @State errorMessage: string = '';
  @State updateTimeLabel: string = '';
  @StorageLink(AppKeys.IS_INITIAL_FETCH_DONE) isInitialFetchDone: boolean = false;
  @State currentSemesterDataLoaded: boolean = false;
  @State hasAnyData: boolean = false;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  private storageService: StorageService | null = null;
  private updateLabelTimer: number = -1;

  private get studentInfo(): StudentInfo | null {
    const str = this.studentInfoStr;
    if (str && str.length > 0) {
      try {
        return JSON.parse(str) as StudentInfo;
      } catch {
        // fall through to cached fallback
      }
    }
    const cached = getCachedStudentInfo();
    return cached ?? null;
  }

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.storageService = new StorageService(context);
    } catch {}
    this.updateTimeLabel = this.computeUpdateLabel();
    this.updateLabelTimer = setInterval(() => {
      this.updateTimeLabel = this.computeUpdateLabel();
    }, 30000);

    // 确保 semesterIndex 在有效范围内（不强制重置为最新，保留用户选择）
    const sems = this.semesters ?? [];
    if (sems.length > 0) {
      if (this.semesterIndex < 0 || this.semesterIndex >= sems.length) {
        this.semesterIndex = sems.length - 1;
      }
      this.updateHasAnyData();
    }

    // 首次进入时检查是否需要获取当前学期数据
    setTimeout(() => {
      this.checkAndFetchCurrentSemesterData();
    }, 200);
  }

  aboutToDisappear(): void {
    if (this.updateLabelTimer !== -1) {
      clearInterval(this.updateLabelTimer);
    }
    // 持久化当前学期索引
    this.storageService?.saveNumber('semester_index', this.semesterIndex);
  }

  private computeUpdateLabel(): string {
    if (this.lastUpdate === 0) return '从未更新';
    const diffMs = Date.now() - this.lastUpdate;
    const diffMins = Math.floor(diffMs / 60000);
    if (diffMins < 1) return '刚刚更新';
    if (diffMins < 60) return `更新于 ${diffMins} 分钟前`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `更新于 ${diffHours} 小时前`;
    return `更新于 ${Math.floor(diffHours / 24)} 天前`;
  }

  private get currentSemester(): Semester | null {
    const sems = this.semesters ?? [];
    if (sems.length === 0) return null;
    const idx = Math.min(Math.max(0, this.semesterIndex), sems.length - 1);
    return sems[idx] ?? null;
  }

  /** 安全获取当前学期的 GPA 信息（防止反序列化后 gpaInfo 为 undefined） */
  private get safeGpaInfo(): GpaInfo {
    const sem = this.currentSemester;
    if (sem !== null && sem !== undefined && sem.gpaInfo !== undefined && sem.gpaInfo !== null) {
      return sem.gpaInfo;
    }
    return new GpaInfo();
  }

  private formatGpa(value: number): string {
    if (this.hideGpa) return '***';
    if (value <= 0) return '-';
    return value.toFixed(2);
  }

  private formatCredits(value: number): string {
    if (value <= 0) return '-';
    return value.toFixed(1);
  }

  private triggerFetchCurrentSemester(): void {
    const sem = this.currentSemester;
    if (sem !== null && sem !== undefined) {
      this.fetchCurrentSemesterData(sem);
    }
  }

  private getGradeDetailNavParam(): GradeDetailNavParam {
    return { semesterIndex: this.semesterIndex };
  }

  private getCourseListNavParam(): SemesterIdParam {
    const sem = this.currentSemester;
    return { semesterId: sem !== null && sem !== undefined ? sem.id : '' };
  }

  private getExamListNavParam(): SemesterIdParam {
    const sem = this.currentSemester;
    return { semesterId: sem !== null && sem !== undefined ? sem.id : '' };
  }

  private getCourseScheduleNavParam(sem: Semester, isFirst: boolean): CourseScheduleParam {
    return { semesterId: sem.id, isFirstHalf: isFirst };
  }

  // 检查当前学期是否有数据，如果没有则获取
  private checkAndFetchCurrentSemesterData(): void {
    const sem = this.currentSemester;
    if (sem && !this.currentSemesterDataLoaded && this.isLoggedIn) {
      console.info('[ScholarPage] Checking if current semester needs data fetch...');
      // 如果当前学期没有课程数据，尝试获取
      if (sem.courses.length === 0 && !this.isRefreshing) {
        this.fetchCurrentSemesterData(sem);
      } else {
        this.currentSemesterDataLoaded = true;
      }
    }
  }

  /** 更新 hasAnyData 状态（在 semesters 变化时调用） */
  private updateHasAnyData(): void {
    const sems = this.semesters ?? [];
    let found = false;
    for (let i = 0; i < sems.length; i++) {
      const s = sems[i];
      if (s.courses !== undefined && s.courses !== null && s.courses.length > 0) {
        found = true;
        break;
      }
    }
    this.hasAnyData = found;
  }

  /** 快速检测是否在校内网（教务系统是否可达），约 3 秒超时 */
  private async testCampusNetworkQuick(): Promise<boolean> {
    const req = http.createHttp();
    try {
      // 注意：JW_BASE = 'https://zdbk.zju.edu.cn/jwglxt'，不需要再加 /jwglxt
      // 之前写成 ${JW_BASE}/jwglxt 导致 URL 错误为 /jwglxt/jwglxt，返回 404
      const resp = await req.request(`${JW_BASE}`, {
        method: http.RequestMethod.GET,
        header: { 'Connection': 'close' },
        connectTimeout: 3000,
        readTimeout: 3000
        // 使用系统默认 DNS，不强制公网 DNS
      });
      const isReachable = resp.responseCode === 200 || resp.responseCode === 302 || resp.responseCode === 301;
      console.info(`[ScholarPage] Campus network test: ${JW_BASE} → ${resp.responseCode}, reachable=${isReachable}`);
      return isReachable;
    } catch (e) {
      console.warn(`[ScholarPage] Campus network test failed: ${(e as Error).message}`);
      return false;
    } finally {
      req.destroy();
    }
  }

  // 并行获取单个学期的数据（用于 fetchData 批量刷新）
  private async fetchSemesterDataParallel(sem: Semester, timeoutMs?: number): Promise<void> {
    console.info(`[ScholarPage] Parallel fetching: ${sem.id}, timeout=${timeoutMs ?? 15000}ms`);
    try {
      const results = await Promise.all([
        fetchGrades(sem.id, timeoutMs),
        fetchCourseSchedule(sem.id, timeoutMs),
        fetchExams(sem.id, timeoutMs),
        fetchTodos(sem.id, timeoutMs)
      ]);
      const gradesResult = results[0];
      const scheduleResult = results[1];
      const examsResult = results[2];
      const todosResult = results[3];

      console.info(`[ScholarPage] ${sem.id} raw results: grades.success=${gradesResult.success} len=${gradesResult.data?.length ?? 0} msg="${gradesResult.message}", schedule.success=${scheduleResult.success} len=${scheduleResult.data?.length ?? 0} msg="${scheduleResult.message}", exams.success=${examsResult.success} len=${examsResult.data?.length ?? 0}, todos.success=${todosResult.success} len=${todosResult.data?.length ?? 0}`);

      if (gradesResult.success && gradesResult.data && gradesResult.data.length > 0) {
        sem.courses = gradesResult.data;
        console.info(`[ScholarPage] ${sem.id}: set ${gradesResult.data.length} courses from grades`);
      } else if (!gradesResult.success) {
        console.warn(`[ScholarPage] ${sem.id}: grades fetch failed: ${gradesResult.message}`);
      }
      if (scheduleResult.success && scheduleResult.data && scheduleResult.data.length > 0) {
        for (const schedCourse of scheduleResult.data) {
          const existing = sem.courses.find(c => c.courseId === schedCourse.courseId);
          if (existing) {
            existing.timeSlots = schedCourse.timeSlots;
          } else {
            sem.courses.push(schedCourse);
          }
        }
        console.info(`[ScholarPage] ${sem.id}: merged ${scheduleResult.data.length} schedule courses, total=${sem.courses.length}`);
      } else if (!scheduleResult.success) {
        console.warn(`[ScholarPage] ${sem.id}: schedule fetch failed: ${scheduleResult.message}`);
      }
      if (examsResult.success && examsResult.data && examsResult.data.length > 0) {
        sem.exams = examsResult.data;
      }
      if (todosResult.success && todosResult.data && todosResult.data.length > 0) {
        sem.todos = todosResult.data;
      }
    } catch (e) {
      console.warn(`[ScholarPage] Failed to fetch data for ${sem.id}: ${(e as Error).message}`);
    }
  }

  // 获取当前学期的数据（成绩、课表等）
  private async fetchCurrentSemesterData(sem: Semester): Promise<void> {
    console.info(`[ScholarPage] Fetching data for semester: ${sem.id}`);
    this.isRefreshing = true;
    this.errorMessage = '';

    try {
      const isCampus = await this.testCampusNetworkQuick();
      const apiTimeout = isCampus ? 15000 : 8000;

      const results = await Promise.all([
        fetchGrades(sem.id, apiTimeout),
        fetchCourseSchedule(sem.id, apiTimeout),
        fetchExams(sem.id, apiTimeout),
        fetchTodos(sem.id, apiTimeout)
      ]);

      const gradesResult = results[0];
      const scheduleResult = results[1];
      const examsResult = results[2];
      const todosResult = results[3];

      console.info(`[ScholarPage] Semester ${sem.id}: grades=${gradesResult.data?.length ?? 0}, schedule=${scheduleResult.data?.length ?? 0}, exams=${examsResult.data?.length ?? 0}, todos=${todosResult.data?.length ?? 0}`);

      // 更新学期数据
      if (gradesResult.success && gradesResult.data) {
        sem.courses = gradesResult.data;
      }
      if (scheduleResult.success && scheduleResult.data) {
        for (const schedCourse of scheduleResult.data) {
          const existing = sem.courses.find(c => c.courseId === schedCourse.courseId);
          if (existing) {
            existing.timeSlots = schedCourse.timeSlots;
          } else {
            sem.courses.push(schedCourse);
          }
        }
      }
      if (examsResult.success && examsResult.data) {
        sem.exams = examsResult.data;
      }
      if (todosResult.success && todosResult.data) {
        sem.todos = todosResult.data;
      }

      // 计算 GPA
      this.computeGpa(sem);

      // 更新 AppStorage
      AppStorage.set(AppKeys.SEMESTERS, [...this.semesters]);
      AppStorage.set(AppKeys.LAST_UPDATE, Date.now());
      await this.storageService?.saveSemesters([...this.semesters]);

      this.currentSemesterDataLoaded = true;
      console.info(`[ScholarPage] Semester data fetch completed`);

      if ((sem.courses?.length ?? 0) === 0 && !isCampus) {
        this.errorMessage = '当前不在校园网，无法获取教务数据。请连接校园 VPN 或在校园网环境下使用。';
      }
    } catch (err) {
      console.error(`[ScholarPage] Semester data fetch error: ${(err as Error).message}`);
      this.errorMessage = '获取学期数据失败，请下拉刷新';
    }

    this.isRefreshing = false;
  }

  // 获取所有学期数据（首次登录时调用）
  async fetchData(): Promise<void> {
    if (!this.isLoggedIn) {
      console.warn('[ScholarPage] Not logged in, cannot fetch data');
      this.navStack.pushPathByName('Login', null);
      return;
    }

    console.info('[ScholarPage] Starting fetchData...');
    this.isRefreshing = true;
    this.errorMessage = '';

    try {
      // 并行获取学期列表 + 检测网络环境，节省等待时间
      console.info('[ScholarPage] Fetching semesters and testing network...');
      const GeneratedDestructArray_1 = await Promise.all([
        fetchSemesters(),
        this.testCampusNetworkQuick()
      ]);const semResult = GeneratedDestructArray_1[0];const isCampusNetwork = GeneratedDestructArray_1[1];
      console.info(`[ScholarPage] Semester result: success=${semResult.success}, count=${semResult.data?.length ?? 0}, msg=${semResult.message}`);
      console.info(`[ScholarPage] Campus network: ${isCampusNetwork}`);

      if (!semResult.success || !semResult.data || semResult.data.length === 0) {
        this.errorMessage = semResult.message || '无法获取学期列表';
        this.isRefreshing = false;
        console.error(`[ScholarPage] Failed to fetch semesters: ${semResult.message}`);
        return;
      }

      // 使用返回的学期列表
      let candidateSemesters: Semester[] = semResult.data;
      console.info(`[ScholarPage] Got ${candidateSemesters.length} candidate semesters`);

      // ═══════════════════════════════════════════════════════
      // 与现有缓存数据合并：保留已有学期的课程/GPA/考试/todo 数据
      // 当设备不在校园网（API 超时返回兜底数据）时，避免覆盖缓存
      // ═══════════════════════════════════════════════════════
      const existingSemesters = this.semesters ?? [];
      if (existingSemesters.length > 0) {
        for (let i = 0; i < candidateSemesters.length; i++) {
          const newSem = candidateSemesters[i];
          const existing = existingSemesters.find((s: Semester) => s.id === newSem.id);
          if (existing) {
            newSem.courses = existing.courses;
            newSem.exams = existing.exams;
            newSem.todos = existing.todos;
            newSem.gpaInfo = existing.gpaInfo;
            console.info(`[ScholarPage] Preserved cached data for ${newSem.id}: ${existing.courses.length} courses`);
          }
        }
      }

      // 获取最近 2 个学期的数据（当前学期 + 上一学期）
      // 校外网环境下使用短超时（8秒）+ 不重试，避免长时间 loading
      const apiTimeout = isCampusNetwork ? 15000 : 8000;
      console.info(`[ScholarPage] API timeout: ${apiTimeout}ms`);

      const semestersToFetch = candidateSemesters.slice(-2);
      console.info(`[ScholarPage] Fetching data for ${semestersToFetch.length} recent semesters (parallel)`);

      // 并行获取所有需要获取的学期数据
      const fetchPromises: Promise<void>[] = [];
      for (const sem of semestersToFetch) {
        const p = this.fetchSemesterDataParallel(sem, apiTimeout);
        fetchPromises.push(p);
      }
      await Promise.all(fetchPromises);
      console.info('[ScholarPage] Parallel semester fetch completed');

      // 打印每个待获取学期的最终数据量
      for (const sem of semestersToFetch) {
        console.info(`[ScholarPage] Semester ${sem.id} final state: ${sem.courses?.length ?? 0} courses, ${sem.exams?.length ?? 0} exams, ${sem.todos?.length ?? 0} todos`);
      }

      // 计算当前（最新）学期的 GPA
      const currentSem = candidateSemesters[candidateSemesters.length - 1];
      if (currentSem) {
        this.computeGpa(currentSem);
        this.currentSemesterDataLoaded = true;
      }

      // 检查是否获取到了任何课程数据
      const fetchedAnyData = semestersToFetch.some((s: Semester) => (s.courses?.length ?? 0) > 0);
      if (!fetchedAnyData && !isCampusNetwork) {
        this.errorMessage = '当前不在校园网，无法获取教务数据。请连接校园 VPN 或在校园网环境下使用。';
        console.warn('[ScholarPage] No data fetched and not on campus network');
      } else if (!fetchedAnyData) {
        this.errorMessage = '未能获取到课程数据，请稍后重试。';
        console.warn('[ScholarPage] No data fetched despite being on campus network');
      }

      // 更新学期列表（默认选中最新学期）
      const updatedSemesters = candidateSemesters;

      AppStorage.set(AppKeys.SEMESTERS, updatedSemesters);
      // semesterIndex 由 @StorageLink 自动持久化到 AppStorage
      // 确保指向最新学期（如果当前超出范围）
      if (this.semesterIndex < 0 || this.semesterIndex >= updatedSemesters.length) {
        this.semesterIndex = Math.max(0, updatedSemesters.length - 1);
      }

      const ts = Date.now();
      AppStorage.set(AppKeys.LAST_UPDATE, ts);
      await this.storageService?.saveSemesters(updatedSemesters);
      await this.storageService?.saveNumber('semester_index', this.semesterIndex);

      console.info(`[ScholarPage] Data fetch completed, saved ${updatedSemesters.length} semesters`);
      AppStorage.set(AppKeys.IS_INITIAL_FETCH_DONE, true);

      // 在后台异步获取学生信息（不阻塞主流程）
      fetchStudentInfo().then((info) => {
        if (info.success && info.name.length > 0) {
          setCachedStudentInfo(info);
          AppStorage.set(AppKeys.STUDENT_INFO, JSON.stringify(info));
          this.storageService?.saveString('student_info', JSON.stringify(info));
          console.info(`[ScholarPage] Student info updated: ${info.name}`);
        } else if (info.success && info.studentId.length > 0 && !isCampusNetwork) {
          // 校外网只能拿到学号，也保存下来
          setCachedStudentInfo(info);
          console.info(`[ScholarPage] Student info partial update: ${info.studentId}`);
        }
      }).catch((e: Error) => {
        console.warn(`[ScholarPage] Failed to fetch student info: ${e.message}`);
      });
    } catch (err) {
      this.errorMessage = `获取失败: ${(err as Error).message}`;
      console.error(`[ScholarPage] Fetch data error: ${this.errorMessage}`);
    }

    this.isRefreshing = false;
    this.updateTimeLabel = this.computeUpdateLabel();
  }

  // 学期切换时获取新学期数据
  private async onSemesterChanged(): Promise<void> {
    const sem = this.currentSemester;
    if (sem && this.isLoggedIn) {
      console.info(`[ScholarPage] Semester changed to: ${sem.id}`);
      this.currentSemesterDataLoaded = false;
      // 如果没有数据，获取数据
      if (sem.courses.length === 0) {
        await this.fetchCurrentSemesterData(sem);
      } else {
        this.currentSemesterDataLoaded = true;
      }
    }
  }

  private computeGpa(semester: Semester): void {
    const courses = semester.courses.filter(c => c.hasGrade && c.credits > 0);
    if (courses.length === 0) return;

    const totalCredits = courses.reduce((sum, c) => sum + c.credits, 0);
    const weightedPct = courses.reduce((sum, c) => sum + c.grade * c.credits, 0);
    const pctGpa = totalCredits > 0 ? weightedPct / totalCredits : 0;

    // 百分制转四分制（近似）
    const toFourPoint = (pct: number): number => {
      if (pct >= 90) return 4.0;
      if (pct >= 85) return 3.7;
      if (pct >= 82) return 3.3;
      if (pct >= 78) return 3.0;
      if (pct >= 75) return 2.7;
      if (pct >= 72) return 2.3;
      if (pct >= 68) return 2.0;
      if (pct >= 64) return 1.5;
      if (pct >= 60) return 1.0;
      return 0;
    };

    const weightedFour = courses.reduce((sum, c) => sum + toFourPoint(c.grade) * c.credits, 0);
    const fourGpa = totalCredits > 0 ? weightedFour / totalCredits : 0;

    semester.gpaInfo.percentageGpa = Math.round(pctGpa * 100) / 100;
    semester.gpaInfo.rawFourPointGpa = Math.round(fourGpa * 100) / 100;
    semester.gpaInfo.fourThreeGpa = Math.min(4.3, fourGpa);
    semester.gpaInfo.fivePointGpa = Math.min(5, pctGpa / 20);
    semester.gpaInfo.totalCredits = totalCredits;
  }

  @Builder
  SemesterSelector() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.semesters, (sem: Semester, idx: number) => {
          Text(sem.name)
            .fontSize(13)
            .fontColor(idx === this.semesterIndex ? Color.White : $r('app.color.text_secondary'))
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(20)
            .backgroundColor(idx === this.semesterIndex ?
              $r('app.color.color_blue') : $r('app.color.progress_bg'))
            .animation({ duration: 200, curve: Curve.EaseOut })
            .onClick(() => {
              this.semesterIndex = idx;
              this.onSemesterChanged();
            })
        }, (sem: Semester) => sem.id)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(48)
  }

  @Builder
  GradeModule() {
    if (this.currentSemester === null || this.currentSemester === undefined) {
      Column() { }
    } else {
      RoundRectangleCardWithForehead({
        foreheadColor: '#4CAF50',
        title: '成绩'
      }) {
        Column({ space: 0 }) {
          // 更新状态
          Row({ space: 6 }) {
            Image($r('sys.media.ohos_ic_public_ok'))
              .width(14).height(14)
              .fillColor($r('app.color.text_tertiary'))
            Text(this.updateTimeLabel)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
          .padding({ left: 16, top: 10, bottom: 8 })

          // 6个统计卡片
          Grid() {
            GridItem() {
              TwoLineCard({ title: '五分制GPA', value: this.formatGpa(this.safeGpaInfo.fivePointGpa) })
                .padding(12)
            }
            GridItem() {
              TwoLineCard({ title: '获得学分', value: this.formatCredits(this.safeGpaInfo.totalCredits) })
                .padding(12)
            }
            GridItem() {
              TwoLineCard({ title: '四分制GPA', value: this.formatGpa(this.safeGpaInfo.fourThreeGpa) })
                .padding(12)
            }
            GridItem() {
              TwoLineCard({ title: '主修均绩', value: this.formatGpa(this.safeGpaInfo.majorGpa) })
                .padding(12)
            }
            GridItem() {
              TwoLineCard({ title: '主修学分', value: this.formatCredits(this.safeGpaInfo.majorCredits) })
                .padding(12)
            }
            GridItem() {
              TwoLineCard({ title: '百分制', value: this.formatGpa(this.safeGpaInfo.percentageGpa) })
                .padding(12)
            }
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(0)
          .rowsGap(0)
          .padding({ left: 8, right: 8, bottom: 8 })
          .onClick(() => {
            this.navStack.pushPathByName('GradeDetail', this.getGradeDetailNavParam());
          })

          // 成绩列表
          if ((this.currentSemester?.courses?.length ?? 0) > 0 && this.currentSemester!.courses.filter((c: Course) => c.hasGrade).length > 0) {
            Divider().strokeWidth(0.5).color($r('app.color.progress_bg')).margin({ left: 16, right: 16 })
            Column() {
              ForEach(
                this.currentSemester!.courses.filter((c: Course) => c.hasGrade),
                (course: Course) => {
                  Row() {
                    Text(course.name)
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (course.grade >= 0) {
                      Text(course.grade.toFixed(0))
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.color_blue'))
                    } else if (course.gradeLevel.length > 0) {
                      Text(course.gradeLevel)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.color_blue'))
                    }
                    Text(`  ${course.credits.toFixed(1)}学分`)
                      .fontSize(12)
                      .fontColor($r('app.color.text_tertiary'))
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                },
                (course: Course) => course.uid
              )
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .onClick(() => {
              this.navStack.pushPathByName('GradeDetail', this.getGradeDetailNavParam());
            })
          }
        }
        .width('100%')
      }
    }
  }

  @Builder
  CourseModule() {
    if (this.currentSemester === null || this.currentSemester === undefined) {
      Column() { }
    } else {
      RoundRectangleCardWithForehead({
        foreheadColor: '#00BCD4',
        title: '课程'
      }) {
        Column({ space: 0 }) {
          Row() {
            this.StatCard('课程', this.currentSemester.courses.length.toString(), () => {
              this.navStack.pushPathByName('CourseList', this.getCourseListNavParam());
            })
            this.StatCard('学分', this.safeGpaInfo.totalCredits.toFixed(1), () => {})
            this.StatCard('考试', this.currentSemester.exams.length.toString(), () => {
              this.navStack.pushPathByName('ExamList', this.getExamListNavParam());
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 8 })

          Row({ space: 8 }) {
            this.HalfCourseCard('前半学期', true, this.currentSemester!)
            this.HalfCourseCard('后半学期', false, this.currentSemester!)
          }
          .padding({ left: 12, right: 12, bottom: 12 })
        }
      }
    }
  }

  @Builder
  StatCard(label: string, value: string, onTap: () => void) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8 })
    .onClick(onTap)
  }

  @Builder
  HalfCourseCard(label: string, isFirst: boolean, sem: Semester) {
    Column({ space: 4 }) {
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary'))
      Text(`${sem.courses.filter(c => c.timeSlots.some(s => s.isFirstHalf === isFirst)).length} 门课`).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.app_background'))
    .onClick(() => {
      this.navStack.pushPathByName('CourseSchedule', this.getCourseScheduleNavParam(sem, isFirst));
    })
  }

  @Builder
  TodoModule() {
    if (this.currentSemester === null || this.currentSemester === undefined) {
      Column() { }
    } else {
      RoundRectangleCardWithForehead({
        foreheadColor: '#E91E63',
        title: '作业'
      }) {
        Column({ space: 0 }) {
          Row() {
            this.StatCard('总计', this.currentSemester.todos.length.toString(), () => {})
            this.StatCard('今日', this.currentSemester.todos.filter((t: Todo) => t.dueTime.getTime() <= Date.now() + 86400000).length.toString(), () => {})
            this.StatCard('本周', this.currentSemester.todos.filter((t: Todo) => t.dueTime.getTime() <= Date.now() + 7 * 86400000).length.toString(), () => {})
          }
          .padding({ left: 12, right: 12, top: 12, bottom: 8 })

          if ((this.currentSemester?.todos?.length ?? 0) > 0) {
            Scroll() {
              Row({ space: 10 }) {
                ForEach(this.currentSemester!.todos.sort((a: Todo, b: Todo) => a.dueTime.getTime() - b.dueTime.getTime()).slice(0, 6), (todo: Todo) => {
                  this.TodoCard(todo)
                })
              }
              .padding({ left: 12, right: 12, bottom: 12 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
          }
        }
      }
    }
  }

  @Builder
  TodoCard(todo: Todo) {
    Column({ space: 6 }) {
      Text(todo.courseName)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .opacity(0.7)
      Text(todo.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(this.formatTodoDate(todo.dueTime))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width(140)
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.app_background'))
    .alignItems(HorizontalAlign.Start)
  }

  private formatTodoDate(date: Date): string {
    return `${date.getMonth() + 1}/${date.getDate()} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  @Builder
  PracticeModule() {
    if (this.currentSemester === null || this.currentSemester === undefined) {
      Column() { }
    } else {
      RoundRectangleCardWithForehead({
        foreheadColor: '#FFAB91',
        title: '实践学分'
      }) {
        Row() {
          this.StatCard('二课分', this.safeGpaInfo.secondCredit.toFixed(1), () => {})
          this.StatCard('三课分', this.safeGpaInfo.thirdCredit.toFixed(1), () => {})
          this.StatCard('四课分', this.safeGpaInfo.fourthCredit.toFixed(1), () => {})
        }
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      }
    }
  }

  @Builder
  StudentInfoCard() {
    if (this.studentInfo !== null && this.studentInfo !== undefined && this.studentInfo.name.length > 0) {
      Column({ space: 6 }) {
        Row({ space: 12 }) {
          // 头像占位
          Column() {
            Text(this.studentInfo.name.substring(0, 1))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .backgroundColor($r('app.color.color_blue'))
          .justifyContent(FlexAlign.Center)

          Column({ space: 4 }) {
            Text(this.studentInfo.name)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Row({ space: 8 }) {
              Text(this.studentInfo.studentId)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              if (this.studentInfo.college.length > 0) {
                Text(this.studentInfo.college)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(16)

        if (this.studentInfo.major.length > 0) {
          Row() {
            Text('专业')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
            Blank()
            Text(this.studentInfo.major)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 12 })
        }
      }
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .margin({ bottom: 4 })
    } else if (this.isLoggedIn) {
      // 简化版：学号 + 网络提示
      Row({ space: 12 }) {
        Column() {
          Text('👤')
            .fontSize(22)
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor($r('app.color.progress_bg'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 2 }) {
          Text(this.username)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('姓名/学院信息需校园网环境获取')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .margin({ bottom: 4 })
    }
  }

  build() {
    Column() {
      // 固定标题栏
      Column() {
        Row() {
          Text('学业')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Blank()

          // 手动刷新按钮
          if (this.isLoggedIn && this.semesters.length > 0) {
            Button({ type: ButtonType.Circle }) {
              if (this.isRefreshing) {
                LoadingProgress()
                  .width(20).height(20)
                  .color($r('app.color.color_blue'))
              } else {
                Text('🔄')
                  .fontSize(16)
              }
            }
            .width(36).height(36)
            .backgroundColor($r('app.color.progress_bg'))
            .onClick(() => {
              if (!this.isRefreshing) {
                this.fetchData();
              }
            })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: this.topRectHeight + 10, bottom: 8 })

        // 搜索栏（点击跳转搜索页）
        SearchBar({
          placeholder: '搜索课程、事项...',
          disabled: true,
          onFocusCallback: () => {
            this.navStack.pushPathByName('Search', null);
          }
        })
          .padding({ left: 16, right: 16, bottom: 8 })
          .onClick(() => {
            this.navStack.pushPathByName('Search', null);
          })

        // 学期选择器
        if (this.semesters.length > 0) {
          this.SemesterSelector()
        }
      }
      .backgroundColor($r('app.color.app_background'))
      .zIndex(1)

      // 内容区域
      if (!this.isLoggedIn) {
        // 未登录
        EmptyView({
          icon: '🎓',
          title: '未登录',
          subtitle: '登录后查看成绩、课程等学业信息',
          actionText: '去登录',
          onAction: () => this.navStack.pushPathByName('Login', null)
        })
      } else if ((this.semesters.length === 0 && this.errorMessage.length === 0) || (this.isRefreshing && !this.hasAnyData)) {
        // 正在加载（仅在没有任何学期数据时显示；有缓存数据时直接显示内容）
        Column() {
          Blank()
          LoadingView({ message: '正在加载学业数据...' })
          Blank()
        }
        .onAppear(() => {
          // 延迟执行，确保 UI 先渲染；仅在确实没有数据且未在刷新时触发
          setTimeout(() => {
            if (!this.hasAnyData && !this.isRefreshing && this.isLoggedIn) {
              console.info('[ScholarPage] No cached data, triggering initial fetch...');
              this.fetchData();
            }
          }, 100);
        })
      } else {
        // 有学期数据，显示内容

        Refresh({ refreshing: $$this.isRefreshing }) {
          Scroll() {
            Column({ space: 16 }) {
              // 错误提示
              if (this.errorMessage.length > 0 && (this.currentSemester === null || this.currentSemester === undefined || (this.currentSemester !== null && this.currentSemester !== undefined && (this.currentSemester.courses?.length ?? 0) === 0))) {
                Column({ space: 12 }) {
                  Text(this.errorMessage)
                    .fontSize(14)
                    .fontColor($r('app.color.color_red'))
                    .textAlign(TextAlign.Center)
                  Button('重新获取数据')
                    .fontSize(14)
                    .backgroundColor($r('app.color.color_blue'))
                    .borderRadius(12)
                    .onClick(() => this.fetchData())
                }
                .padding(20)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(16)
              }

              // 学生信息卡片
              this.StudentInfoCard()

              // 当前学期数据卡片
              if (this.currentSemester !== null && this.currentSemester !== undefined) {
                // 显示学期信息
                Row() {
                  Text(this.currentSemester.name)
                    .fontSize(15)
                    .fontColor($r('app.color.text_secondary'))
                    .fontWeight(FontWeight.Medium)
                  Blank()
                  if (this.currentSemester !== null && this.currentSemester !== undefined && (this.currentSemester.courses?.length ?? 0) === 0 && !this.isRefreshing) {
                    Text('点击刷新获取数据')
                      .fontSize(12)
                      .fontColor($r('app.color.color_blue'))
                      .onClick(() => this.triggerFetchCurrentSemester())
                  }
                }
                .padding({ left: 4, right: 4, bottom: 4 })

                this.GradeModule()
                this.CourseModule()

                if (!this.isGrs) {
                  this.TodoModule()
                  this.PracticeModule()
                }
              }

              // 空数据提示
              if (this.currentSemester !== null && this.currentSemester !== undefined && (this.currentSemester.courses?.length ?? 0) === 0 && !this.isRefreshing && this.errorMessage.length === 0) {
                Column({ space: 12 }) {
                  Text('暂无数据')
                    .fontSize(16)
                    .fontColor($r('app.color.text_secondary'))
                  Text('下拉刷新或点击上方按钮获取数据')
                    .fontSize(13)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .padding(20)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(16)
                .width('100%')
              }

              Blank().height(64 + this.bottomRectHeight + 20)
            }
            .padding({ left: 16, right: 16, top: 8 })
          }
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .onRefreshing(() => {
          this.fetchData();
        })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
  private onSemestersChanged(): void {
    const sems = this.semesters ?? [];
    const semLen = sems.length;
    // 更新 hasAnyData 状态
    this.updateHasAnyData();
    // 确保 semesterIndex 在有效范围内
    if (semLen > 0) {
      if (this.semesterIndex < 0 || this.semesterIndex >= semLen) {
        this.semesterIndex = semLen - 1;
        console.info(`[ScholarPage] semesters updated, auto-corrected index to: ${this.semesterIndex}`);
      }
    }
  }

  private onLoginStateChanged(): void {
    const sems = this.semesters ?? [];
    if (this.isLoggedIn && !this.isInitialFetchDone && sems.length === 0 && !this.isRefreshing) {
      console.info('[ScholarPage] Login state changed to true, triggering data fetch...');
      this.fetchData();
    }
  }

  onPageShow(): void {
    console.info(`[ScholarPage] onPageShow: semesters=${(this.semesters ?? []).length}, index=${this.semesterIndex}, hasAnyData=${this.hasAnyData}`);
    const sems = this.semesters ?? [];
    if (sems.length > 0) {
      // 确保 semesterIndex 指向有效学期
      const validIndex = Math.min(Math.max(0, this.semesterIndex), sems.length - 1);
      if (this.semesterIndex !== validIndex) {
        this.semesterIndex = validIndex;
        console.info(`[ScholarPage] onPageShow corrected semesterIndex to ${validIndex}`);
      }
      this.updateHasAnyData();
    }
  }
}

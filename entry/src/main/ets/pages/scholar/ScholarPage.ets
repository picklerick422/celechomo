// ScholarPage.ets - 学业信息主页

import http from '@ohos.net.http';
import { Semester, GpaInfo } from '../../model/Semester';
import { Todo, Course } from '../../model/Course';
import { colorFromUid } from '../../model/Period';
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
  @State _currentSemester: Semester | null = null;
  @State safeGpaInfoValue: GpaInfo = new GpaInfo();
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

    // 确保 semesterIndex 在有效范围内，且默认指向时间上的当前学期
    const sems = this.semesters ?? [];
    if (sems.length > 0) {
      if (this.semesterIndex < 0 || this.semesterIndex >= sems.length) {
        this.semesterIndex = sems.length - 1;
        console.info(`[ScholarPage] Corrected semesterIndex to last: ${this.semesterIndex}`);
        this.syncCurrentSemester();
      }
      // 首次进入时，默认指向时间上的当前学期（提升用户体验）
      const ts = this.thisSemester;
      if (ts) {
        const idx = sems.findIndex(s => s.id === ts.id);
        if (idx >= 0 && idx !== this.semesterIndex) {
          const currentHasData = (sems[this.semesterIndex]?.courses?.length ?? 0) > 0;
          if (!currentHasData) {
            this.semesterIndex = idx;
            console.info(`[ScholarPage] Init semesterIndex to thisSemester: ${idx}, id=${ts.id}`);
            this.syncCurrentSemester();
          }
        }
      }
    }
    // 必须始终更新 hasAnyData，避免清除缓存后旧值残留导致 loading 死锁
    this.updateHasAnyData();

    // 同步当前学期（即使 semesterIndex 未被修改）
    this.syncCurrentSemester();

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

  /** 同步 _currentSemester 状态变量（在 semesterIndex 变化后调用） */
  private syncCurrentSemester(): void {
    const sems = this.semesters ?? [];
    if (sems.length === 0) {
      this._currentSemester = null;
      return;
    }
    const idx = Math.min(Math.max(0, this.semesterIndex), sems.length - 1);
    this._currentSemester = sems[idx] ?? null;
    this.updateSafeGpaInfo();
    console.info(`[ScholarPage] syncCurrentSemester: idx=${idx}, id=${this._currentSemester?.id ?? 'null'}, courses=${this._currentSemester?.courses?.length ?? 0}`);
  }

  /** 时间上的当前学期（FlowPage 数据获取用）：包含当前日期或最接近的学期 */
  private get thisSemester(): Semester | null {
    const sems = this.semesters ?? [];
    if (sems.length === 0) return null;
    const now = Date.now();
    let best: Semester | null = null;
    let bestDist = Infinity;
    for (const sem of sems) {
      const s = sem.startDate.getTime();
      const e = sem.endDate.getTime();
      if (isNaN(s) || isNaN(e)) continue;
      // 当前日期在学期内（含结束后7天宽限）→ 直接选中
      if (now >= s && now <= e + 7 * 86400000) {
        return sem;
      }
      const dist = Math.min(Math.abs(now - s), Math.abs(now - e));
      if (dist < bestDist) {
        bestDist = dist;
        best = sem;
      }
    }
    return best ?? sems[sems.length - 1] ?? null;
  }

  /** 更新 safeGpaInfoValue（在 syncCurrentSemester 中调用） */
  private updateSafeGpaInfo(): void {
    const sem = this._currentSemester;
    if (sem !== null && sem !== undefined && sem.gpaInfo !== undefined && sem.gpaInfo !== null) {
      this.safeGpaInfoValue = sem.gpaInfo;
    } else {
      this.safeGpaInfoValue = new GpaInfo();
    }
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

  /** 按学期 ID 过滤课程（API 可能返回全部学期的数据） */
  private filterCoursesBySemester(courses: Course[], semesterId: string): Course[] {
    const parts = semesterId.split('-');
    if (parts.length < 3 || courses.length === 0) return courses;
    const year = `${parts[0]}-${parts[1]}`;   // "2025-2026"
    const shortYear = parts[0];                 // "2025"
    const termNum = parseInt(parts[2]);
    // xqm 可能是 "3"/"12"（教务标准）或 "1"/"2"（简化格式）
    const expectedTerms = termNum === 1 ? ['3', '1'] : ['12', '2'];

    const filtered = courses.filter(c => {
      if (!c.semester || c.semester.length === 0) return false;
      const cParts = c.semester.split('-');

      // 格式1: "2025-2026-12" (3段, 范围-year + term)
      if (cParts.length >= 3) {
        const cYear = cParts.slice(0, 2).join('-');
        const cTerm = cParts[cParts.length - 1];
        return cYear === year && expectedTerms.includes(cTerm);
      }

      // 格式2: "2025-12" (2段, 单年 + term) — API 返回的 xnm 可能是单年
      if (cParts.length === 2) {
        const cShortYear = cParts[0];
        const cTerm = cParts[1];
        return cShortYear === shortYear && expectedTerms.includes(cTerm);
      }

      return c.semester === semesterId;
    });
    console.info(`[ScholarPage] Filtered ${courses.length} -> ${filtered.length} courses for ${semesterId}`);
    return filtered;
  }

  private triggerFetchCurrentSemester(): void {
    const sem = this._currentSemester;
    if (sem !== null && sem !== undefined) {
      this.fetchCurrentSemesterData(sem);
    }
  }

  private getGradeDetailNavParam(): GradeDetailNavParam {
    return { semesterIndex: this.semesterIndex };
  }

  private getCourseListNavParam(): SemesterIdParam {
    const sem = this._currentSemester;
    return { semesterId: sem !== null && sem !== undefined ? sem.id : '' };
  }

  private getExamListNavParam(): SemesterIdParam {
    const sem = this._currentSemester;
    return { semesterId: sem !== null && sem !== undefined ? sem.id : '' };
  }

  private getCourseScheduleNavParam(sem: Semester, isFirst: boolean): CourseScheduleParam {
    return { semesterId: sem.id, isFirstHalf: isFirst };
  }

  // 检查时间上的当前学期是否有数据，如果没有则获取（用于FlowPage课表数据）
  private checkAndFetchCurrentSemesterData(): void {
    const sem = this.thisSemester;
    if (sem && this.isLoggedIn && !this.isRefreshing) {
      const hasCourses = (sem.courses?.length ?? 0) > 0;
      console.info(`[ScholarPage] Check fetch thisSemester=${sem.id}: hasCourses=${hasCourses}, loaded=${this.currentSemesterDataLoaded}`);
      // 如果当前学期没有课程数据，或从未加载过，尝试获取
      if (!hasCourses || !this.currentSemesterDataLoaded) {
        if (!hasCourses) {
          this.currentSemesterDataLoaded = false;
        }
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
        fetchExams(sem.id, timeoutMs, sem.startDate, sem.endDate),
        fetchTodos(sem.id, timeoutMs)
      ]);
      const gradesResult = results[0];
      const scheduleResult = results[1];
      const examsResult = results[2];
      const todosResult = results[3];

      console.info(`[ScholarPage] ${sem.id} raw results: grades.success=${gradesResult.success} len=${gradesResult.data?.length ?? 0} msg="${gradesResult.message}", schedule.success=${scheduleResult.success} len=${scheduleResult.data?.length ?? 0} msg="${scheduleResult.message}", exams.success=${examsResult.success} len=${examsResult.data?.length ?? 0}, todos.success=${todosResult.success} len=${todosResult.data?.length ?? 0}`);

      // 以课表数据为基础创建课程列表（课表API可能返回全年课程，需按semester过滤）
      let courses: Course[] = [];
      if (scheduleResult.success && scheduleResult.data && scheduleResult.data.length > 0) {
        // 过滤出属于当前半学期的课表课程（根据xxq字段推断）
        const filteredSchedule = scheduleResult.data.filter(c => {
          // 如果课程明确标识了学期，且与当前学期不同，过滤掉
          if (c.semester && c.semester.length > 0 && c.semester !== '-') {
            return c.semester === sem.id;
          }
          // 学期信息不明确，保留（保守策略）
          return true;
        });
        courses = filteredSchedule.map(c => c);
        if (filteredSchedule.length !== scheduleResult.data.length) {
          console.info(`[ScholarPage] ${sem.id}: filtered schedule ${scheduleResult.data.length} → ${filteredSchedule.length} courses by semester`);
        }
      }

      // 将成绩数据匹配到课表课程（成绩API可能返回全部历史数据）
      if (gradesResult.success && gradesResult.data && gradesResult.data.length > 0) {
        // 先用 filterCoursesBySemester 过滤出属于当前学期的成绩，避免同名课程跨学期匹配错误
        let currentGrades = this.filterCoursesBySemester(gradesResult.data, sem.id);
        console.info(`[ScholarPage] ${sem.id}: ${gradesResult.data.length} total grades, ${currentGrades.length} have valid semester info`);

        // 回退：如果 xkkh 解析失败导致过滤后为空，直接按名称匹配课表课程（近似方案）
        const useFallback = currentGrades.length === 0 && gradesResult.data.length > 0;
        if (useFallback) {
          console.warn(`[ScholarPage] ${sem.id}: xkkh parse failed for all grades, falling back to name-based matching`);
        }

        const gradesToMatch = useFallback ? gradesResult.data : currentGrades;

        for (const gradeCourse of gradesToMatch) {
          // 按课程号或名称匹配课表课程
          const matchById = gradeCourse.courseId.length > 0
            ? courses.find(c => c.courseId === gradeCourse.courseId)
            : undefined;
          const matchByName = !matchById && gradeCourse.name.length > 0
            ? courses.find(c => c.name === gradeCourse.name)
            : undefined;
          const match = matchById ?? matchByName;

          if (match) {
            // 匹配成功，将成绩信息赋给课表课程
            match.grade = gradeCourse.grade;
            match.gradePoint = gradeCourse.gradePoint;
            match.gradeLevel = gradeCourse.gradeLevel;
            // 如果课表课程缺少学分信息，使用成绩的
            if (match.credits <= 0 && gradeCourse.credits > 0) {
              match.credits = gradeCourse.credits;
            }
          } else if (!useFallback) {
            // 属于当前学期但没有匹配的课表课程，添加为独立课程
            courses.push(gradeCourse);
          }
          // fallback 模式下：不添加不匹配的课程（避免混入其他学期）
        }
        console.info(`[ScholarPage] ${sem.id}: final ${courses.length} courses (${useFallback ? 'fallback' : 'semester-filtered'} mode)`);
      } else if (!gradesResult.success) {
        console.warn(`[ScholarPage] ${sem.id}: grades fetch failed: ${gradesResult.message}`);
      }

      sem.courses = courses;
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
        fetchExams(sem.id, apiTimeout, sem.startDate, sem.endDate),
        fetchTodos(sem.id, apiTimeout)
      ]);

      const gradesResult = results[0];
      const scheduleResult = results[1];
      const examsResult = results[2];
      const todosResult = results[3];

      console.info(`[ScholarPage] Semester ${sem.id}: grades=${gradesResult.data?.length ?? 0}, schedule=${scheduleResult.data?.length ?? 0}, exams=${examsResult.data?.length ?? 0}, todos=${todosResult.data?.length ?? 0}`);

      // 以课表数据为基础创建课程列表（课表API可能返回全年课程，需按semester过滤）
      let courses: Course[] = [];
      if (scheduleResult.success && scheduleResult.data) {
        const filteredSchedule = scheduleResult.data.filter(c => {
          if (c.semester && c.semester.length > 0 && c.semester !== '-') {
            return c.semester === sem.id;
          }
          return true;
        });
        courses = filteredSchedule.map(c => c);
        if (filteredSchedule.length !== scheduleResult.data.length) {
          console.info(`[ScholarPage] ${sem.id}: filtered schedule ${scheduleResult.data.length} → ${filteredSchedule.length} courses by semester`);
        }
      }

      // 将成绩数据匹配到课表课程（成绩API可能返回全部历史数据）
      if (gradesResult.success && gradesResult.data) {
        // 先用 filterCoursesBySemester 过滤出属于当前学期的成绩，避免同名课程跨学期匹配错误
        let currentGrades = this.filterCoursesBySemester(gradesResult.data, sem.id);
        console.info(`[ScholarPage] ${sem.id}: ${gradesResult.data.length} total grades, ${currentGrades.length} have valid semester info`);

        // 回退：如果 xkkh 解析失败导致过滤后为空，直接按名称匹配课表课程（近似方案）
        const useFallback = currentGrades.length === 0 && gradesResult.data.length > 0;
        if (useFallback) {
          console.warn(`[ScholarPage] ${sem.id}: xkkh parse failed for all grades, falling back to name-based matching`);
        }

        const gradesToMatch = useFallback ? gradesResult.data : currentGrades;

        for (const gradeCourse of gradesToMatch) {
          const matchById = gradeCourse.courseId.length > 0
            ? courses.find(c => c.courseId === gradeCourse.courseId)
            : undefined;
          const matchByName = !matchById && gradeCourse.name.length > 0
            ? courses.find(c => c.name === gradeCourse.name)
            : undefined;
          const match = matchById ?? matchByName;

          if (match) {
            match.grade = gradeCourse.grade;
            match.gradePoint = gradeCourse.gradePoint;
            match.gradeLevel = gradeCourse.gradeLevel;
            if (match.credits <= 0 && gradeCourse.credits > 0) {
              match.credits = gradeCourse.credits;
            }
          } else if (!useFallback) {
            courses.push(gradeCourse);
          }
        }
        console.info(`[ScholarPage] Set ${courses.length} courses for ${sem.id} (${useFallback ? 'fallback' : 'semester-filtered'} mode)`);
      } else {
        console.info(`[ScholarPage] Set ${courses.length} courses for ${sem.id} from schedule only`);
      }

      sem.courses = courses;
      if (examsResult.success && examsResult.data) {
        sem.exams = examsResult.data;
      }
      if (todosResult.success && todosResult.data) {
        sem.todos = todosResult.data;
      }

      // 计算 GPA
      this.computeGpa(sem);

      // 更新 AppStorage（触发 @StorageLink 更新）
      const updatedSems = [...this.semesters];
      AppStorage.set(AppKeys.SEMESTERS, updatedSems);
      AppStorage.set(AppKeys.LAST_UPDATE, Date.now());
      await this.storageService?.saveSemesters(updatedSems);

      this.currentSemesterDataLoaded = true;
      this.updateHasAnyData();
      console.info(`[ScholarPage] Fetch completed for ${sem.id}: ${sem.courses.length} courses, ${sem.exams.length} exams, ${sem.todos.length} todos`);

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
      // 与现有缓存数据合并：仅当旧缓存有效时才保留，避免空缓存覆盖新数据
      // 当设备不在校园网（API 超时返回兜底数据）时，避免覆盖缓存
      // ═══════════════════════════════════════════════════════
      const existingSemesters = this.semesters ?? [];
      if (existingSemesters.length > 0) {
        for (let i = 0; i < candidateSemesters.length; i++) {
          const newSem = candidateSemesters[i];
          const existing = existingSemesters.find((s: Semester) => s.id === newSem.id);
          if (existing) {
            // 缓存合并策略：新数据优先，仅当新数据为空时才保留旧缓存
            const hasNewCourses = (newSem.courses?.length ?? 0) > 0;
            const hasOldCourses = (existing.courses?.length ?? 0) > 0;
            const hasNewGpa = newSem.gpaInfo !== undefined && newSem.gpaInfo !== null &&
              (newSem.gpaInfo.totalCredits > 0 || newSem.gpaInfo.fivePointGpa > 0);
            const hasOldGpa = existing.gpaInfo !== undefined && existing.gpaInfo !== null &&
              (existing.gpaInfo.totalCredits > 0 || existing.gpaInfo.fivePointGpa > 0);
            // 课程：新数据优先
            if (!hasNewCourses && hasOldCourses) {
              newSem.courses = existing.courses;
            }
            if ((newSem.exams?.length ?? 0) === 0 && (existing.exams?.length ?? 0) > 0) {
              newSem.exams = existing.exams;
            }
            if ((newSem.todos?.length ?? 0) === 0 && (existing.todos?.length ?? 0) > 0) {
              newSem.todos = existing.todos;
            }
            // GPA：新数据优先
            if (!hasNewGpa && hasOldGpa) {
              newSem.gpaInfo = existing.gpaInfo;
            }
            console.info(`[ScholarPage] Merged cache for ${newSem.id}: newCourses=${newSem.courses?.length ?? 0}, oldCourses=${hasOldCourses ? existing.courses.length : 0}`);
          }
        }
      }

      // 获取所有学期的数据（分批串行，避免过多并发请求）
      // 校外网环境下使用短超时（8秒）+ 不重试，避免长时间 loading
      const apiTimeout = isCampusNetwork ? 15000 : 8000;
      console.info(`[ScholarPage] API timeout: ${apiTimeout}ms`);

      const semestersToFetch = candidateSemesters;
      console.info(`[ScholarPage] Fetching data for all ${semestersToFetch.length} semesters (batch size=2)`);

      // 分批串行获取：每批 2 个学期并行，批与批之间串行
      const batchSize = 2;
      for (let i = 0; i < semestersToFetch.length; i += batchSize) {
        const batch = semestersToFetch.slice(i, i + batchSize);
        console.info(`[ScholarPage] Fetching batch ${Math.floor(i / batchSize) + 1}: ${batch.map(s => s.id).join(', ')}`);
        const promises = batch.map(sem => this.fetchSemesterDataParallel(sem, apiTimeout));
        await Promise.all(promises);
      }
      console.info('[ScholarPage] All semester fetches completed');

      // 打印每个学期的最终数据量，并计算 GPA
      for (const sem of semestersToFetch) {
        console.info(`[ScholarPage] Semester ${sem.id} final state: ${sem.courses?.length ?? 0} courses, ${sem.exams?.length ?? 0} exams, ${sem.todos?.length ?? 0} todos`);
        if ((sem.courses?.length ?? 0) > 0) {
          this.computeGpa(sem);
        }
      }

      // 标记最新学期数据已加载
      const currentSem = candidateSemesters[candidateSemesters.length - 1];
      if (currentSem) {
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

      // 更新学期列表
      const updatedSemesters = candidateSemesters;

      AppStorage.set(AppKeys.SEMESTERS, updatedSemesters);
      // semesterIndex 由 @StorageLink 自动持久化到 AppStorage
      // 只修正越界索引；首次加载时若当前学期无数据，才自动切换到最新有数据的学期
      let targetIndex = this.semesterIndex;
      if (targetIndex < 0 || targetIndex >= updatedSemesters.length) {
        targetIndex = updatedSemesters.length - 1;
      }
      // 仅在首次加载（isInitialFetchDone=false）且当前学期无数据时，自动选择有数据的学期
      if (!this.isInitialFetchDone && (updatedSemesters[targetIndex]?.courses?.length ?? 0) === 0) {
        for (let i = updatedSemesters.length - 1; i >= 0; i--) {
          if ((updatedSemesters[i].courses?.length ?? 0) > 0) {
            targetIndex = i;
            break;
          }
        }
      }
      if (this.semesterIndex !== targetIndex) {
        this.semesterIndex = targetIndex;
        console.info(`[ScholarPage] fetchData auto-selected semester index: ${targetIndex}`);
        this.syncCurrentSemester();
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
    const sem = this._currentSemester;
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
      Row({ space: 6 }) {
        ForEach(this.semesters, (sem: Semester, idx: number) => {
          Text(sem.name)
            .fontSize(12)
            .fontWeight(idx === this.semesterIndex ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(idx === this.semesterIndex ? Color.White : $r('app.color.text_secondary'))
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .borderRadius(10)
            .backgroundColor(idx === this.semesterIndex ?
              $r('app.color.color_blue') : 'rgba(0,0,0,0.04)')
            .animation({ duration: 180, curve: Curve.EaseOut })
            .onClick(() => {
              this.semesterIndex = idx;
              this.syncCurrentSemester();
              this.onSemesterChanged();
            })
        }, (sem: Semester) => sem.id)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(44)
  }

  @Builder
  GradeModule() {
    if (this._currentSemester === null || this._currentSemester === undefined) {
      Column() { }
    } else {
      // 使用独立卡片（与 CourseModule 保持一致）
      Column({ space: 0 }) {
        // 额头条
        Row() {
          Text('📈 成绩')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          Blank()
        }
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.color_blue'))
        .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 0, bottomRight: 0 })

        // 内容区
        Column({ space: 0 }) {
          // 统计行（与 CourseModule 的 StatCard 样式一致）
          Row() {
            this.StatCard('五分制GPA', this.formatGpa(this.safeGpaInfoValue.fivePointGpa), () => {
              this.navStack.pushPathByName('GradeDetail', this.getGradeDetailNavParam());
            })
            this.StatCard('获得学分', this.formatCredits(this.safeGpaInfoValue.totalCredits), () => {
              this.navStack.pushPathByName('GradeDetail', this.getGradeDetailNavParam());
            })
            this.StatCard('百分制', this.formatGpa(this.safeGpaInfoValue.percentageGpa), () => {
              this.navStack.pushPathByName('GradeDetail', this.getGradeDetailNavParam());
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 8 })

          Row() {
            this.StatCard('四分制GPA', this.formatGpa(this.safeGpaInfoValue.fourThreeGpa), () => {
              this.navStack.pushPathByName('GradeDetail', this.getGradeDetailNavParam());
            })
            this.StatCard('主修均绩', this.formatGpa(this.safeGpaInfoValue.majorGpa), () => {
              this.navStack.pushPathByName('GradeDetail', this.getGradeDetailNavParam());
            })
            this.StatCard('主修学分', this.formatCredits(this.safeGpaInfoValue.majorCredits), () => {
              this.navStack.pushPathByName('GradeDetail', this.getGradeDetailNavParam());
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 8 })

          // ── 成绩列表 ──
          if (this._currentSemester!.courses.filter((c: Course) => c.hasGrade).length > 0) {
            Divider().strokeWidth(0.5).color($r('app.color.progress_bg')).margin({ left: 12, right: 12 })

            Column({ space: 0 }) {
              Row() {
                Text('本学期成绩')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary'))
                Blank()
                Text('查看全部 →')
                  .fontSize(12)
                  .fontColor($r('app.color.color_blue'))
                  .onClick(() => {
                    this.navStack.pushPathByName('GradeDetail', this.getGradeDetailNavParam());
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 6 })

              Column({ space: 0 }) {
                ForEach(
                  this._currentSemester!.courses.filter((c: Course) => c.hasGrade),
                  (course: Course, index: number) => {
                    this.CourseListItem(course)
                    if (index < this._currentSemester!.courses.filter((c: Course) => c.hasGrade).length - 1) {
                      Divider()
                        .strokeWidth(0.5)
                        .color($r('app.color.progress_bg'))
                        .margin({ left: 32 })
                    }
                  },
                  (course: Course) => course.uid
                )
              }
              .width('100%')
              .padding({ bottom: 4 })
            }
          }
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 16, bottomRight: 16 })
        .padding({ bottom: 4 })
      }
      .width('100%')
      .borderRadius(16)
      .shadow({
        radius: 16,
        color: $r('app.color.shadow_color'),
        offsetX: 0,
        offsetY: 4
      })
    }
  }

  @Builder
  CourseModule() {
    if (this._currentSemester === null || this._currentSemester === undefined) {
      Column() { }
    } else {
      // 使用独立卡片（不用 RoundRectangleCardWithForehead，避免 clip 问题）
      Column({ space: 0 }) {
        // 额头条
        Row() {
          Text('📚 课程')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          Blank()
        }
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.color_blue'))
        .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 0, bottomRight: 0 })

        // 内容区
        Column({ space: 0 }) {
          // 统计行
          Row() {
            this.StatCard('📖 课程', this._currentSemester.courses.length.toString(), () => {
              this.navStack.pushPathByName('CourseList', this.getCourseListNavParam());
            })
            this.StatCard('📊 学分', this.safeGpaInfoValue.totalCredits.toFixed(1), () => {})
            this.StatCard('📝 考试', this._currentSemester.exams.length.toString(), () => {
              this.navStack.pushPathByName('ExamList', this.getExamListNavParam());
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 8 })

          // 前后半学期卡片
          Row({ space: 8 }) {
            this.HalfCourseCard(this._currentSemester!.isSpring ? '春学期' : '秋学期', true, this._currentSemester!)
            this.HalfCourseCard(this._currentSemester!.isSpring ? '夏学期' : '冬学期', false, this._currentSemester!)
          }
          .padding({ left: 12, right: 12, bottom: 8 })

          // ── 课程列表 ──
          Divider().strokeWidth(0.5).color($r('app.color.progress_bg')).margin({ left: 12, right: 12 })

          Column({ space: 0 }) {
            Row() {
              Text('本学期课程')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
              Blank()
              if (this._currentSemester.courses.length > 0) {
                Text('查看全部 →')
                  .fontSize(12)
                  .fontColor($r('app.color.color_blue'))
                  .onClick(() => {
                    this.navStack.pushPathByName('CourseList', this.getCourseListNavParam());
                  })
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 6 })

            if (this._currentSemester.courses.length > 0) {
              Column({ space: 0 }) {
                ForEach(this._currentSemester.courses, (course: Course, index: number) => {
                  this.CourseListItem(course)
                  if (index < this._currentSemester!.courses.length - 1) {
                    Divider()
                      .strokeWidth(0.5)
                      .color($r('app.color.progress_bg'))
                      .margin({ left: 32 })
                  }
                }, (course: Course) => course.uid)
              }
              .width('100%')
              .padding({ bottom: 4 })
            } else {
              Text('暂无课程数据，下拉刷新获取')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .padding({ left: 12, right: 12, bottom: 10 })
            }
          }
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 16, bottomRight: 16 })
        .padding({ bottom: 4 })
      }
      .width('100%')
      .borderRadius(16)
      .shadow({
        radius: 16,
        color: $r('app.color.shadow_color'),
        offsetX: 0,
        offsetY: 4
      })
    }
  }

  @Builder
  CourseListItem(course: Course) {
    Row({ space: 12 }) {
      // 左侧圆形色块（课程首字）
      Column() {
        Text(course.name.length > 0 ? course.name.substring(0, 1) : '?')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .backgroundColor(colorFromUid(course.uid))
      .justifyContent(FlexAlign.Center)

      // 中间内容
      Column({ space: 3 }) {
        Text(course.name.length > 0 ? course.name : '未命名课程')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          if (course.teacher.length > 0) {
            Text(course.teacher)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (course.credits > 0) {
            Text(`${course.credits.toFixed(1)} 学分`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          if (!course.hasGrade && course.credits > 0) {
            Text('进行中')
              .fontSize(10)
              .fontColor('#4CAF50')
              .padding({ left: 4, right: 4 })
              .backgroundColor('#E8F5E9')
              .borderRadius(4)
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧成绩
      Column({ space: 2 }) {
        if (course.hasGrade) {
          Text(course.grade.toFixed(0))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getGradeColor(course.grade))
          if (course.gradePoint >= 0) {
            Text(`绩点 ${course.gradePoint.toFixed(1)}`)
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
          }
        } else if (course.credits === 0) {
          Text('未完结')
            .fontSize(11)
            .fontColor('#FF9800')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#FFF3E0')
            .borderRadius(6)
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .onClick(() => {
      this.navStack.pushPathByName('GradeDetail', this.getGradeDetailNavParam());
    })
  }

  private getGradeColor(grade: number): ResourceColor {
    if (grade >= 90) return '#4CAF50';
    if (grade >= 80) return '#2196F3';
    if (grade >= 60) return '#FF9800';
    return '#F44336';
  }

  private getGradeLabel(grade: number): string {
    if (grade >= 90) return '优秀';
    if (grade >= 80) return '良好';
    if (grade >= 70) return '中等';
    if (grade >= 60) return '及格';
    return '不及格';
  }

  @Builder
  StatCard(label: string, value: string, onTap: () => void) {
    Column({ space: 6 }) {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_blue'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .backgroundColor('rgba(0,0,0,0.02)')
    .borderRadius(10)
    .onClick(onTap)
  }

  @Builder
  HalfCourseCard(label: string, isFirst: boolean, sem: Semester) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 4 }) {
        Text(`${sem.courses.filter(c => c.timeSlots && c.timeSlots.some(s => (isFirst ? s.halfType === 'first' : s.halfType === 'second'))).length}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_blue'))
        Text('门')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding({ top: 4 })
      }
    }
    .layoutWeight(1)
    .padding(12)
    .borderRadius(12)
    .backgroundColor('rgba(0,0,0,0.03)')
    .onClick(() => {
      this.navStack.pushPathByName('CourseSchedule', this.getCourseScheduleNavParam(sem, isFirst));
    })
  }

  @Builder
  TodoModule() {
    if (this._currentSemester === null || this._currentSemester === undefined) {
      Column() { }
    } else {
      RoundRectangleCardWithForehead({
        foreheadColor: '#FF7043',
        title: '📋 作业'
      }) {
        Column({ space: 0 }) {
          Row() {
            this.StatCard('📋 总计', this._currentSemester.todos.length.toString(), () => {})
            this.StatCard('⏰ 今日', this._currentSemester.todos.filter((t: Todo) => t.dueTime.getTime() <= Date.now() + 86400000).length.toString(), () => {})
            this.StatCard('📅 本周', this._currentSemester.todos.filter((t: Todo) => t.dueTime.getTime() <= Date.now() + 7 * 86400000).length.toString(), () => {})
          }
          .padding({ left: 12, right: 12, top: 12, bottom: 8 })

          if ((this._currentSemester?.todos?.length ?? 0) > 0) {
            Scroll() {
              Row({ space: 10 }) {
                ForEach(this._currentSemester!.todos.sort((a: Todo, b: Todo) => a.dueTime.getTime() - b.dueTime.getTime()).slice(0, 6), (todo: Todo) => {
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
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(todo.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Row({ space: 4 }) {
        Text('⏰')
          .fontSize(10)
        Text(this.formatTodoDate(todo.dueTime))
          .fontSize(10)
          .fontColor(this.getTodoUrgencyColor(todo.dueTime))
      }
    }
    .width(140)
    .height(110)
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: 'rgba(0,0,0,0.06)' })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  private getTodoUrgencyColor(dueTime: Date): string {
    const diff = dueTime.getTime() - Date.now();
    if (diff < 0) return '#F44336'; // 已过期 红色
    if (diff < 86400000) return '#FF9800'; // 24小时内 橙色
    if (diff < 3 * 86400000) return '#FFC107'; // 3天内 黄色
    return '#9E9E9E'; // 其他 灰色
  }

  private formatTodoDate(date: Date): string {
    return `${date.getMonth() + 1}/${date.getDate()} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  @Builder
  PracticeModule() {
    if (this._currentSemester === null || this._currentSemester === undefined) {
      Column() { }
    } else {
      RoundRectangleCardWithForehead({
        foreheadColor: '#AB47BC',
        title: '🔬 实践学分'
      }) {
        Row() {
          this.StatCard('🏃 二课', this.safeGpaInfoValue.secondCredit.toFixed(1), () => {})
          this.StatCard('🌿 三课', this.safeGpaInfoValue.thirdCredit.toFixed(1), () => {})
          this.StatCard('🔬 四课', this.safeGpaInfoValue.fourthCredit.toFixed(1), () => {})
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
          // 延迟执行，确保 UI 先渲染；在 semesters 为空或确实没有数据时触发
          setTimeout(() => {
            if ((!this.hasAnyData || this.semesters.length === 0) && !this.isRefreshing && this.isLoggedIn) {
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
              if (this.errorMessage.length > 0 && (this._currentSemester === null || this._currentSemester === undefined || (this._currentSemester !== null && this._currentSemester !== undefined && (this._currentSemester.courses?.length ?? 0) === 0))) {
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
              if (this._currentSemester !== null && this._currentSemester !== undefined) {
                // 显示学期信息
                Row() {
                  Text(this._currentSemester.name)
                    .fontSize(15)
                    .fontColor($r('app.color.text_secondary'))
                    .fontWeight(FontWeight.Medium)
                  Blank()
                  if (this._currentSemester !== null && this._currentSemester !== undefined && (this._currentSemester.courses?.length ?? 0) === 0 && !this.isRefreshing) {
                    Text('点击刷新获取数据')
                      .fontSize(12)
                      .fontColor($r('app.color.color_blue'))
                      .onClick(() => this.triggerFetchCurrentSemester())
                  }
                }
                .padding({ left: 4, right: 4, bottom: 4 })

                // 诊断信息（调试用，确认数据状态）
                Row() {
                  Text(`📊 ${this._currentSemester!.name} | 课程${this._currentSemester!.courses.length} | 考试${this._currentSemester!.exams.length} | 作业${this._currentSemester!.todos.length}`)
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .padding({ left: 4, bottom: 4 })

                this.GradeModule()
                this.CourseModule()

                if (!this.isGrs) {
                  this.TodoModule()
                  this.PracticeModule()
                }
              }

              // 空数据提示
              if (this._currentSemester !== null && this._currentSemester !== undefined && (this._currentSemester.courses?.length ?? 0) === 0 && !this.isRefreshing && this.errorMessage.length === 0) {
                Column({ space: 12 }) {
                  Text('📭')
                    .fontSize(40)
                  Text('暂无课程数据')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_secondary'))
                  Text('下拉刷新或点击上方按钮获取数据')
                    .fontSize(13)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .padding(32)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(16)
                .width('100%')
                .alignItems(HorizontalAlign.Center)
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
    // 只修正越界索引，不因"没有数据"而切换学期（用户选了哪个就显示哪个）
    if (semLen > 0) {
      let needChange = false;
      let bestIndex = this.semesterIndex;
      if (bestIndex < 0 || bestIndex >= semLen) {
        bestIndex = semLen - 1;
        needChange = true;
      }
      if (needChange) {
        this.semesterIndex = bestIndex;
        console.info(`[ScholarPage] semesters updated, corrected index to: ${this.semesterIndex}`);
      }
    }
    // 无论索引是否变化，都同步当前学期（@StorageLink 数据可能已更新）
    this.syncCurrentSemester();
  }

  private onLoginStateChanged(): void {
    const sems = this.semesters ?? [];
    if (!this.isLoggedIn || this.isRefreshing) return;
    if (sems.length === 0) {
      // 首次登录，没有学期数据，获取全部
      console.info('[ScholarPage] Login state changed, no semesters, triggering fetchData...');
      this.fetchData();
    } else {
      // 已登录且有学期数据，检查当前学期是否需要刷新
      console.info('[ScholarPage] Login state changed, checking current semester data...');
      this.checkAndFetchCurrentSemesterData();
    }
  }

  onPageShow(): void {
    const curSem = this._currentSemester;
    const thisSem = this.thisSemester;
    console.info(`[ScholarPage] onPageShow: semesters=${(this.semesters ?? []).length}, index=${this.semesterIndex}, currentSemester=${curSem?.id ?? 'null'}(courses=${curSem?.courses?.length ?? 0}), thisSemester=${thisSem?.id ?? 'null'}(courses=${thisSem?.courses?.length ?? 0}), hasAnyData=${this.hasAnyData}`);
    const sems = this.semesters ?? [];
    if (sems.length > 0) {
      // 只修正越界索引，不因"没有数据"而切换学期
      const validIndex = Math.min(Math.max(0, this.semesterIndex), sems.length - 1);
      if (this.semesterIndex !== validIndex) {
        this.semesterIndex = validIndex;
        console.info(`[ScholarPage] onPageShow corrected semesterIndex to ${validIndex}`);
        this.syncCurrentSemester();
      }
    }
    // 必须始终更新 hasAnyData，避免清除缓存后旧值残留
    this.updateHasAnyData();
    // 同步当前学期（即使 semesterIndex 未被修改）
    this.syncCurrentSemester();
    // 页面显示时检查并获取当前学期数据
    this.checkAndFetchCurrentSemesterData();
  }
}

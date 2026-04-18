// Index.ets - 主入口页面，包含全局状态管理和底部 Tab 导航

import common from '@ohos.app.ability.common';
import { Task } from '../model/Task';
import { Period } from '../model/Period';
import { Semester, TimeRange } from '../model/Semester';
import { StorageService } from '../service/StorageService';
import { generateFlowList } from '../service/FlowService';
import { setCookies, checkUpdate, setStudentId, setCachedStudentInfo, StudentInfo } from '../service/NetworkService';
import { FlowPage } from './flow/FlowPage';
import { CalendarPage } from './calendar/CalendarPage';
import { TaskPage } from './task/TaskPage';
import { ScholarPage } from './scholar/ScholarPage';
import { OptionPage } from './option/OptionPage';
import { TaskEditPage } from './task/TaskEditPage';
import { GradeDetailPage } from './scholar/GradeDetailPage';
import { CourseListPage } from './scholar/CourseListPage';
import { CourseSchedulePage } from './scholar/CourseSchedulePage';
import { ExamListPage } from './scholar/ExamListPage';
import { SearchPage } from './SearchPage';
import { LoginPage } from './option/LoginPage';
import { ECardPayPage } from './option/ECardPayPage';
import { AllowTimeEditPage } from './option/AllowTimeEditPage';
import { CourseIdMappingEditPage } from './option/CourseIdMappingEditPage';
import { CreditsPage } from './option/CreditsPage';
import { ServiceTermsPage } from './option/ServiceTermsPage';
import { DiagnosticPage } from './option/DiagnosticPage';
import curves from '@ohos.curves';

// ============= 全局状态 Key =============
export const AppKeys: Record<string, string> = {
  "FLOW_LIST": 'flowList',
  "TASKS": 'tasks',
  "SEMESTERS": 'semesters',
  "CURRENT_SEMESTER_INDEX": 'semesterIndex',
  "USERNAME": 'username',
  "IS_LOGGED_IN": 'isLoggedIn',
  "IS_GRS": 'isGrs',
  "HIDE_GPA": 'hideGpa',
  "GPA_CALC_MODE": 'gpaCalcMode',
  "WORK_DURATION": 'workDuration',
  "REST_DURATION": 'restDuration',
  "ALLOW_TIMES": 'allowTimes',
  "THEME_MODE": 'themeMode',
  "LAST_UPDATE": 'lastUpdate',
  "PUSH_GRADE": 'pushGrade',
  "SYNC_CALENDAR": 'syncCalendar',
  "COURSE_MAPPING": 'courseMapping',
  "LATEST_VERSION": 'latestVersion',
  "APP_VERSION": 'appVersion',
  "STUDENT_INFO": 'studentInfo',
  "topRectHeight": 'topRectHeight',
  "bottomRectHeight": 'bottomRectHeight'
};

export type ThemeMode = 'light' | 'dark' | 'system';

const CURRENT_VERSION = '1.2.0';

// ============= NavDestination 路由映射 =============
@Builder
function pageMap(name: string, param: ESObject) {
  if (name === 'TaskEdit') {
    TaskEditPage()
  } else if (name === 'GradeDetail') {
    GradeDetailPage()
  } else if (name === 'CourseList') {
    CourseListPage()
  } else if (name === 'CourseSchedule') {
    CourseSchedulePage()
  } else if (name === 'ExamList') {
    ExamListPage()
  } else if (name === 'Search') {
    SearchPage()
  } else if (name === 'Login') {
    LoginPage()
  } else if (name === 'ECardPay') {
    ECardPayPage()
  } else if (name === 'AllowTimeEdit') {
    AllowTimeEditPage()
  } else if (name === 'CourseIdMapping') {
    CourseIdMappingEditPage()
  } else if (name === 'Credits') {
    CreditsPage()
  } else if (name === 'ServiceTerms') {
    ServiceTermsPage()
  } else if (name === 'Diagnostic') {
    DiagnosticPage()
  }
}

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  private navStack: NavPathStack = new NavPathStack();
  @StorageLink(AppKeys.FLOW_LIST) flowList: Period[] = [];
  @StorageLink(AppKeys.TASKS) tasks: Task[] = [];
  @StorageLink(AppKeys.SEMESTERS) @Watch('onSemestersChanged') semesters: Semester[] = [];
  @StorageLink(AppKeys.USERNAME) username: string = '';
  @StorageLink(AppKeys.IS_LOGGED_IN) isLoggedIn: boolean = false;
  @StorageLink(AppKeys.LATEST_VERSION) latestVersion: string = '';
  @StorageLink(AppKeys.APP_VERSION) appVersion: string = CURRENT_VERSION;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;

  private storageService: StorageService | null = null;
  private tabController: TabsController = new TabsController();
  private refreshTimer: number = -1;

  /** 初始化 AppStorage 默认值 */
  private initAppStorage(): void {
    AppStorage.setOrCreate(AppKeys.FLOW_LIST, [] as Period[]);
    AppStorage.setOrCreate(AppKeys.TASKS, [] as Task[]);
    AppStorage.setOrCreate(AppKeys.SEMESTERS, [] as Semester[]);
    AppStorage.setOrCreate(AppKeys.USERNAME, '');
    AppStorage.setOrCreate(AppKeys.IS_LOGGED_IN, false);
    AppStorage.setOrCreate(AppKeys.IS_GRS, false);
    AppStorage.setOrCreate(AppKeys.HIDE_GPA, false);
    AppStorage.setOrCreate(AppKeys.GPA_CALC_MODE, 'highest');
    AppStorage.setOrCreate(AppKeys.WORK_DURATION, 50);
    AppStorage.setOrCreate(AppKeys.REST_DURATION, 10);
    AppStorage.setOrCreate(AppKeys.ALLOW_TIMES, [] as TimeRange[]);
    AppStorage.setOrCreate(AppKeys.THEME_MODE, 'system');
    AppStorage.setOrCreate(AppKeys.LAST_UPDATE, 0);
    AppStorage.setOrCreate(AppKeys.PUSH_GRADE, false);
    AppStorage.setOrCreate(AppKeys.SYNC_CALENDAR, false);
    AppStorage.setOrCreate(AppKeys.COURSE_MAPPING, {} as Record<string, string>);
    AppStorage.setOrCreate(AppKeys.LATEST_VERSION, '');
    AppStorage.setOrCreate(AppKeys.APP_VERSION, CURRENT_VERSION);
    AppStorage.setOrCreate(AppKeys.STUDENT_INFO, '');
    AppStorage.setOrCreate('semesterIndex', 0);
    AppStorage.setOrCreate('topRectHeight', 0);
    AppStorage.setOrCreate('bottomRectHeight', 0);
  }

  async aboutToAppear(): Promise<void> {
    this.initAppStorage();
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.storageService = new StorageService(context);
    } catch {}
    await this.loadPersistedData();
    // 延迟检查更新
    setTimeout(() => { this.checkForUpdate(); }, 1500);
    // 每分钟刷新任务状态
    this.refreshTimer = setInterval(() => { this.refreshTaskStatuses(); }, 60000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
    }
  }

  private async loadPersistedData(): Promise<void> {
    if (!this.storageService) return;
    const results = await Promise.all([
      this.storageService.loadTasks(),
      this.storageService.loadSemesters(),
      this.storageService.loadAllowTimes(),
      this.storageService.loadWorkDuration(),
      this.storageService.loadRestDuration(),
      this.storageService.loadHideGpa(),
      this.storageService.loadGpaCalcMode(),
      this.storageService.loadIsGrs(),
      this.storageService.loadUsername(),
      this.storageService.loadLastUpdate(),
      this.storageService.loadString('cookies', ''),
      this.storageService.loadString('student_info', '')
    ]);

    const tasks = results[0];
    const semesters = results[1];
    const allowTimes = results[2];
    const workDuration = results[3];
    const restDuration = results[4];
    const hideGpa = results[5];
    const gpaCalcMode = results[6];
    const isGrs = results[7];
    const username = results[8];
    const lastUpdate = results[9];
    const cookies = results[10];
    const studentInfoStr = results[11] as string;

    AppStorage.set(AppKeys.TASKS, tasks);
    AppStorage.set(AppKeys.SEMESTERS, semesters);
    AppStorage.set(AppKeys.ALLOW_TIMES, allowTimes.length > 0 ? allowTimes :
      [new TimeRange(8 * 60, 12 * 60), new TimeRange(14 * 60, 22 * 60)]);
    AppStorage.set(AppKeys.WORK_DURATION, workDuration);
    AppStorage.set(AppKeys.REST_DURATION, restDuration);
    AppStorage.set(AppKeys.HIDE_GPA, hideGpa);
    AppStorage.set(AppKeys.GPA_CALC_MODE, gpaCalcMode);
    AppStorage.set(AppKeys.IS_GRS, isGrs);
    AppStorage.set(AppKeys.USERNAME, username);
    AppStorage.set(AppKeys.IS_LOGGED_IN, username.length > 0);
    AppStorage.set(AppKeys.LAST_UPDATE, lastUpdate);
    if (cookies.length > 0) setCookies(cookies);
    // 恢复学号到 NetworkService（避免重启后 savedStudentId 为空）
    if (username.length > 0 && username !== 'web_user') {
      setStudentId(username);
    }
    // 恢复学生信息缓存
    if (studentInfoStr.length > 0) {
      try {
        const studentInfo = JSON.parse(studentInfoStr) as StudentInfo;
        setCachedStudentInfo(studentInfo);
        AppStorage.set(AppKeys.STUDENT_INFO, studentInfoStr);
      } catch {
        console.warn('[Index] Failed to parse cached student info');
      }
    }
    // 重建 flowList
    this.rebuildFlowList(tasks, semesters,
      allowTimes.length > 0 ? allowTimes : [new TimeRange(8 * 60, 12 * 60), new TimeRange(14 * 60, 22 * 60)],
      workDuration, restDuration);
  }

  /** 学期数据更新时自动重建 flowList（ScholarPage fetchData 完成后触发） */
  onSemestersChanged(): void {
    const semesters = AppStorage.get<Semester[]>(AppKeys.SEMESTERS) ?? [];
    if (semesters.length === 0) return;
    const tasks = AppStorage.get<Task[]>(AppKeys.TASKS) ?? [];
    const allowTimes = AppStorage.get<TimeRange[]>(AppKeys.ALLOW_TIMES) ??
      [new TimeRange(8 * 60, 12 * 60), new TimeRange(14 * 60, 22 * 60)];
    const workDuration = AppStorage.get<number>(AppKeys.WORK_DURATION) ?? 50;
    const restDuration = AppStorage.get<number>(AppKeys.REST_DURATION) ?? 10;
    this.rebuildFlowList(tasks, semesters, allowTimes, workDuration, restDuration);
  }

  private rebuildFlowList(tasks: Task[], semesters: Semester[], allowTimes: TimeRange[],
    workDuration: number, restDuration: number): void {
    const list = generateFlowList(tasks, semesters, allowTimes, workDuration, restDuration);
    AppStorage.set(AppKeys.FLOW_LIST, list);
  }

  private refreshTaskStatuses(): void {
    const now = new Date();
    const tasks = AppStorage.get<Task[]>(AppKeys.TASKS) ?? [];
    let changed = false;
    for (const task of tasks) {
      const s = task.computeStatus(now);
      if (s !== task.status) { task.status = s; changed = true; }
    }
    if (changed) AppStorage.set(AppKeys.TASKS, [...tasks]);
  }

  private async checkForUpdate(): Promise<void> {
    try {
      const result = await checkUpdate();
      if (result.success && result.data) {
        const v = (result.data as string).replace(/^v/, '');
        AppStorage.set(AppKeys.LATEST_VERSION, v);
        if (this.isNewer(v, CURRENT_VERSION)) {
          try {
            this.getUIContext().getPromptAction().showDialog({
              title: '更新可用',
              message: `Celechron ${v} 已发布，建议更新以获得最新功能和修复。`,
              buttons: [
                { text: '访问网站', color: '#000000' },
                { text: '忽略', color: '#000000' }
              ]
            });
          } catch {}
        }
      }
    } catch {}
  }

  private isNewer(a: string, b: string): boolean {
    const p = (v: string) => v.split('.').map(Number);
    const av = p(a), bv = p(b);
    for (let i = 0; i < 3; i++) {
      if ((av[i] ?? 0) > (bv[i] ?? 0)) return true;
      if ((av[i] ?? 0) < (bv[i] ?? 0)) return false;
    }
    return false;
  }

  // ======= 颜色辅助方法 =======

  /** 各 Tab 的强调色（图标、标签使用） */
  private getTabColor(index: number): string {
    const colors = ['#667eea', '#00BCD4', '#f093fb', '#5856D6', '#636366'];
    return colors[index] || '#667eea';
  }

  /** 各 Tab 选中药丸背景色（#AARRGGBB 格式，约 15% 不透明度） */
  private getTabPillBg(index: number): string {
    const colors = ['#26667eea', '#2600BCD4', '#26f093fb', '#265856D6', '#26636366'];
    return colors[index] || '#26667eea';
  }

  private getTabGradientStart(index: number): string {
    return this.getTabColor(index);
  }

  private getTabGradientEnd(index: number): string {
    const colors = ['#764ba2', '#00ACC1', '#f5576c', '#3f51b5', '#48484A'];
    return colors[index] || '#764ba2';
  }

  // ======= Tab 构建块 =======

  /**
   * 系统图标型 Tab（接下来页面）
   * 选中时：彩色图标 + 半透明药丸背景 + 彩色标签
   * 未选中时：灰色图标 + 灰色标签
   */
  @Builder
  TabItem(index: number, icon: Resource, label: string) {
    Column({ space: 4 }) {
      Stack() {
        // 选中状态药丸背景（光感晕染）
        Column()
          .width(48).height(32)
          .borderRadius(16)
          .backgroundColor(this.getTabPillBg(index))
          .opacity(this.currentIndex === index ? 1 : 0)
          .animation({ duration: 250, curve: Curve.EaseOut })
        // 图标
        Image(icon)
          .width(22).height(22)
          .fillColor(this.currentIndex === index
            ? this.getTabColor(index)
            : $r('app.color.text_tertiary'))
          .scale({
            x: this.currentIndex === index ? 1.12 : 1.0,
            y: this.currentIndex === index ? 1.12 : 1.0
          })
          .animation({ duration: 300, curve: Curve.EaseOut })
      }
      .width(48).height(32)

      Text(label)
        .fontSize(10)
        .fontColor(this.currentIndex === index
          ? this.getTabColor(index)
          : $r('app.color.text_tertiary'))
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Regular)
        .animation({ duration: 200, curve: Curve.EaseOut })
    }
    .padding({ top: 8, bottom: 4 })
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  /**
   * Emoji 型 Tab（日程/任务/学业/设置）
   * 选中时：全彩 Emoji + 半透明药丸背景 + 彩色标签
   * 未选中时：半透明 Emoji + 灰色标签
   */
  @Builder
  TabItemWithEmoji(index: number, emoji: string, label: string) {
    Column({ space: 4 }) {
      Stack() {
        // 选中状态药丸背景（光感晕染）
        Column()
          .width(48).height(32)
          .borderRadius(16)
          .backgroundColor(this.getTabPillBg(index))
          .opacity(this.currentIndex === index ? 1 : 0)
          .animation({ duration: 250, curve: Curve.EaseOut })
        // Emoji 图标
        Text(emoji)
          .fontSize(20)
          .opacity(this.currentIndex === index ? 1.0 : 0.45)
          .scale({
            x: this.currentIndex === index ? 1.15 : 1.0,
            y: this.currentIndex === index ? 1.15 : 1.0
          })
          .animation({ duration: 300, curve: Curve.EaseOut })
      }
      .width(48).height(32)

      Text(label)
        .fontSize(10)
        .fontColor(this.currentIndex === index
          ? this.getTabColor(index)
          : $r('app.color.text_tertiary'))
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Regular)
        .animation({ duration: 200, curve: Curve.EaseOut })
    }
    .padding({ top: 8, bottom: 4 })
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Navigation(this.navStack) {
      Tabs({
        barPosition: BarPosition.End,
        controller: this.tabController,
        index: this.currentIndex
      }) {
        TabContent() {
          FlowPage({ navStack: this.navStack })
        }
        .tabBar(this.TabItem(0, $r('sys.media.ohos_ic_public_clock'), '接下来'))

        TabContent() {
          CalendarPage({ navStack: this.navStack })
        }
        .tabBar(this.TabItemWithEmoji(1, '📅', '日程'))

        TabContent() {
          TaskPage({ navPathStack: this.navStack })
        }
        .tabBar(this.TabItemWithEmoji(2, '📝', '任务'))

        TabContent() {
          ScholarPage({ navStack: this.navStack })
        }
        .tabBar(this.TabItemWithEmoji(3, '🎓', '学业'))

        TabContent() {
          OptionPage({ navStack: this.navStack })
        }
        .tabBar(this.TabItemWithEmoji(4, '⚙️', '设置'))
      }
      .barHeight(64)
      .barBackgroundColor($r('app.color.tab_bar_bg'))
      .barBackgroundBlurStyle(BlurStyle.Regular)
      .barOverlap(true)
      .animationDuration(300)
      .scrollable(true)
      .onChange((index: number) => { this.currentIndex = index; })
    }
    .navDestination(pageMap)
    .hideTitleBar(true)
    .hideToolBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.app_background'))
    .backgroundBlurStyle(BlurStyle.NONE)
    .expandSafeArea([], [SafeAreaEdge.BOTTOM])
  }
}

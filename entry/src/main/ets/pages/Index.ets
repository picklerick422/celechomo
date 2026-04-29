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
import { CourseDetailPage } from './scholar/CourseDetailPage';
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
import { HdsNavigation, HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
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
  "TAB_BAR_STYLE": 'tabBarStyle',
  "LAST_UPDATE": 'lastUpdate',
  "PUSH_GRADE": 'pushGrade',
  "SYNC_CALENDAR": 'syncCalendar',
  "COURSE_MAPPING": 'courseMapping',
  "LATEST_VERSION": 'latestVersion',
  "APP_VERSION": 'appVersion',
  "STUDENT_INFO": 'studentInfo',
  "IS_INITIAL_FETCH_DONE": 'isInitialFetchDone',
  "topRectHeight": 'topRectHeight',
  "bottomRectHeight": 'bottomRectHeight'
};

export type ThemeMode = 'light' | 'dark' | 'system';
export type TabBarStyle = 'glow' | 'pill';

const CURRENT_VERSION = '1.2.0';

// ============= NavDestination 路由映射 =============
@Builder
function pageMap(name: string, param: ESObject) {
  if (name === 'TaskEdit') {
    TaskEditPage()
  } else if (name === 'GradeDetail') {
    GradeDetailPage()
  } else if (name === 'CourseDetail') {
    CourseDetailPage()
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
  @StorageLink(AppKeys.TAB_BAR_STYLE) tabBarStyle: string = 'glow';
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;

  // 胶囊样式底栏交互状态(切 tab 时方向喷射粒子)
  @State pillTabMotionDirection: number = 0; // -1=向左 0=静止 1=向右

  private storageService: StorageService | null = null;
  private tabController: TabsController = new TabsController();
  private hdsTabController: HdsTabsController = new HdsTabsController();
  private refreshTimer: number = -1;
  private readonly tabCount: number = 5;
  // 胶囊底栏几何常量
  private readonly iconOnlyCellWidth: number = 56;
  private readonly expandedCellWidth: number = 130;
  private readonly pillBarHeight: number = 60;
  private readonly pillIndicatorHeight: number = 54;

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
    AppStorage.setOrCreate(AppKeys.TAB_BAR_STYLE, 'glow');
    AppStorage.setOrCreate(AppKeys.LAST_UPDATE, 0);
    AppStorage.setOrCreate(AppKeys.PUSH_GRADE, false);
    AppStorage.setOrCreate(AppKeys.SYNC_CALENDAR, false);
    AppStorage.setOrCreate(AppKeys.COURSE_MAPPING, {} as Record<string, string>);
    AppStorage.setOrCreate(AppKeys.LATEST_VERSION, '');
    AppStorage.setOrCreate(AppKeys.APP_VERSION, CURRENT_VERSION);
    AppStorage.setOrCreate(AppKeys.STUDENT_INFO, '');
    AppStorage.setOrCreate(AppKeys.IS_INITIAL_FETCH_DONE, false);
    AppStorage.setOrCreate(AppKeys.CURRENT_SEMESTER_INDEX, 0);
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
      this.storageService.loadString('student_info', ''),
      this.storageService.loadBoolean('isInitialFetchDone', false),
      this.storageService.loadNumber('semester_index', 0),
      this.storageService.loadThemeMode(),
      this.storageService.loadTabBarStyle()
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
    const isInitialFetchDone = results[12] as boolean;
    const semesterIndex = results[13] as number;
    const themeMode = results[14] as string;
    const tabBarStyle = results[15] as string;

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
    AppStorage.set(AppKeys.IS_INITIAL_FETCH_DONE, isInitialFetchDone);
    AppStorage.set(AppKeys.CURRENT_SEMESTER_INDEX, semesterIndex);
    AppStorage.set(AppKeys.THEME_MODE, themeMode);
    AppStorage.set(AppKeys.TAB_BAR_STYLE, tabBarStyle);
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
                { text: '访问网站', color: $r('app.color.text_primary') },
                { text: '忽略', color: $r('app.color.text_primary') }
              ]
            }).catch(() => {
              // TODO: Implement error handling.
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

  // ======= HDS 沉浸光感 Tab 图标配置 =======
  private getTabNormalIcon(index: number): SymbolGlyphModifier {
    const icons = [
      $r('sys.symbol.alarm_fill_1'),
      $r('sys.symbol.worldclock_fill_2'),
      $r('sys.symbol.stopwatch_2'),
      $r('sys.symbol.square_and_pencil'),
      $r('sys.symbol.star')
    ];
    return new SymbolGlyphModifier(icons[index] ?? icons[0])
      .fontColor(['#8E8E93'])
      .fontSize(22);
  }

  private getTabSelectedIcon(index: number): SymbolGlyphModifier {
    const icons = [
      $r('sys.symbol.alarm_fill_1'),
      $r('sys.symbol.worldclock_fill_2'),
      $r('sys.symbol.stopwatch_2'),
      $r('sys.symbol.square_and_pencil'),
      $r('sys.symbol.star')
    ];
    return new SymbolGlyphModifier(icons[index] ?? icons[0])
      .fontColor([this.getTabColor(index)])
      .fontSize(27)
      .fontWeight(FontWeight.Bold);
  }

  private getTabLabel(index: number): string {
    const labels = ['接下来', '日程', '任务', '学业', '设置'];
    return labels[index] ?? '';
  }

  // ======= 胶囊样式底栏 - 辅助方法 =======

  /** 系统符号图标(与 GlowTabsBody 共用一套) */
  private getTabSymbolResource(index: number): Resource {
    const icons: Resource[] = [
      $r('sys.symbol.alarm_fill_1'),
      $r('sys.symbol.worldclock_fill_2'),
      $r('sys.symbol.stopwatch_2'),
      $r('sys.symbol.square_and_pencil'),
      $r('sys.symbol.star')
    ];
    return icons[index] ?? icons[0];
  }

  /** 第 i 个 cell 的宽度(选中态展开,其余收缩为图标条) */
  private cellWidth(i: number): number {
    return i === this.currentIndex ? this.expandedCellWidth : this.iconOnlyCellWidth;
  }

  /** 第 i 个 cell 的左边缘 x(累加前面 cell 的宽度) */
  private cellLeftEdge(i: number): number {
    let x = 0;
    for (let k = 0; k < i; k++) {
      x += this.cellWidth(k);
    }
    return x;
  }

  /** 指示器相对内层 Stack 的水平偏移(2px 内嵌) */
  private pillIndicatorOffsetX(): number {
    return 2 + this.cellLeftEdge(this.currentIndex);
  }

  /** 整条胶囊底栏的总宽度(恒定:1 个展开 cell + 其余 icon-only cell) */
  private totalPillBarWidth(): number {
    return this.expandedCellWidth + this.iconOnlyCellWidth * (this.tabCount - 1);
  }

  /** 切换到指定 tab:动画 currentIndex,保持 Tabs 内容同步 */
  private snapToTab(idx: number): void {
    const target = Math.max(0, Math.min(this.tabCount - 1, idx));
    const isSame = target === this.currentIndex;

    if (target > this.currentIndex) {
      this.pillTabMotionDirection = 1;
    } else if (target < this.currentIndex) {
      this.pillTabMotionDirection = -1;
    } else {
      this.pillTabMotionDirection = 0;
    }

    try {
      this.getUIContext().animateTo({
        duration: 320,
        curve: Curve.FastOutSlowIn,
        onFinish: () => {
          this.pillTabMotionDirection = 0;
        }
      }, () => {
        this.currentIndex = target;
      });
    } catch {
      this.currentIndex = target;
      this.pillTabMotionDirection = 0;
    }

    if (!isSame) {
      try { this.tabController.changeIndex(target); } catch {}
    }
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

  // ======= 胶囊样式底栏 =======
  /**
   * 胶囊样式底栏:
   * - 毛玻璃材质背景胶囊(自动适配深浅色)
   * - 蓝色指示器:尺寸=展开 cell 宽,offsetX 跟随 currentIndex,与各 cell 的宽度变化在同一段缓动里同步
   * - 5 个 cell:点击切换;选中态横向展开为图标+文字,其余仅图标
   */
  @Builder
  PillTabBar() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Start }) {
        // 1. 毛玻璃背景胶囊
        Row()
          .width(this.totalPillBarWidth())
          .height(this.pillBarHeight)
          .borderRadius(this.pillBarHeight / 2)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .border({ width: 0.5, color: '#10000000' })
          .shadow({
            radius: 16,
            color: '#1A000000',
            offsetX: 0,
            offsetY: 6
          })

        // 2. 蓝色指示器(滑动+变宽到选中 cell)
        Stack() {
          Row()
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.color_blue'))

          // 粒子层(切 tab 时按方向喷射)
          Particle({
            particles: [
              {
                // 0 号:环境闪烁
                emitter: {
                  particle: {
                    type: ParticleType.POINT,
                    config: { radius: 1.0 },
                    count: -1,
                    lifetime: 800,
                    lifetimeRange: 200
                  },
                  emitRate: 0,
                  shape: ParticleEmitterShape.RECTANGLE,
                  position: [0, 0],
                  size: ['100%', '100%']
                },
                color: { range: ['#FFFFFFFF', '#FFFFFFFF'] },
                opacity: {
                  range: [0.0, 1.0],
                  updater: {
                    type: ParticleUpdater.CURVE,
                    config: [
                      { from: 0.0, to: 1.0, startMillis: 0, endMillis: 200 },
                      { from: 1.0, to: 0.0, startMillis: 200, endMillis: 800 }
                    ]
                  }
                },
                scale: { range: [0.4, 1.4] },
                velocity: { speed: [3, 10], angle: [0, 360] }
              },
              {
                // 1 号:向右喷射
                emitter: {
                  particle: {
                    type: ParticleType.POINT,
                    config: { radius: 1.3 },
                    count: -1,
                    lifetime: 500,
                    lifetimeRange: 200
                  },
                  emitRate: 0,
                  shape: ParticleEmitterShape.RECTANGLE,
                  position: [0, 0],
                  size: ['100%', '100%']
                },
                color: { range: ['#FFFFFFFF', '#FFFFFFFF'] },
                opacity: {
                  range: [0.0, 1.0],
                  updater: {
                    type: ParticleUpdater.CURVE,
                    config: [
                      { from: 0.0, to: 1.0, startMillis: 0, endMillis: 100 },
                      { from: 1.0, to: 0.0, startMillis: 100, endMillis: 500 }
                    ]
                  }
                },
                scale: { range: [0.4, 1.6] },
                velocity: { speed: [60, 120], angle: [-25, 25] }
              },
              {
                // 2 号:向左喷射
                emitter: {
                  particle: {
                    type: ParticleType.POINT,
                    config: { radius: 1.3 },
                    count: -1,
                    lifetime: 500,
                    lifetimeRange: 200
                  },
                  emitRate: 0,
                  shape: ParticleEmitterShape.RECTANGLE,
                  position: [0, 0],
                  size: ['100%', '100%']
                },
                color: { range: ['#FFFFFFFF', '#FFFFFFFF'] },
                opacity: {
                  range: [0.0, 1.0],
                  updater: {
                    type: ParticleUpdater.CURVE,
                    config: [
                      { from: 0.0, to: 1.0, startMillis: 0, endMillis: 100 },
                      { from: 1.0, to: 0.0, startMillis: 100, endMillis: 500 }
                    ]
                  }
                },
                scale: { range: [0.4, 1.6] },
                velocity: { speed: [60, 120], angle: [155, 205] }
              }
            ]
          })
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.None)
            .emitter([
              { index: 0, emitRate: 0 },
              { index: 1, emitRate: this.pillTabMotionDirection > 0 ? 80 : 0 },
              { index: 2, emitRate: this.pillTabMotionDirection < 0 ? 80 : 0 }
            ])
        }
        .width(this.expandedCellWidth - 4)
        .height(this.pillIndicatorHeight)
        .borderRadius(this.pillIndicatorHeight / 2)
        .clip(true)
        .shadow({
          radius: 10,
          color: '#40007AFF',
          offsetX: 0,
          offsetY: 4
        })
        .offset({ x: this.pillIndicatorOffsetX(), y: 0 })
        .hitTestBehavior(HitTestMode.None)

        // 3. Cell 层:点击切换 + 选中态横向展开显示文字
        Row() {
          ForEach([0, 1, 2, 3, 4], (i: number) => {
            Row({ space: 6 }) {
              SymbolGlyph(this.getTabSymbolResource(i))
                .fontSize(22)
                .fontColor(i === this.currentIndex ? [Color.White] : ['#8E8E93'])
                .fontWeight(FontWeight.Medium)

              if (i === this.currentIndex) {
                Text(this.getTabLabel(i))
                  .fontSize(14)
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Medium)
                  .maxLines(1)
                  .transition(
                    TransitionEffect.OPACITY
                      .combine(TransitionEffect.translate({ x: -8, y: 0 }))
                      .animation({ duration: 260, curve: Curve.FastOutSlowIn })
                  )
              }
            }
            .width(this.cellWidth(i))
            .height(this.pillBarHeight)
            .justifyContent(FlexAlign.Center)
            .onClick(() => this.snapToTab(i))
            .hitTestBehavior(HitTestMode.Transparent)
          }, (i: number) => `pill-cell-${i}`)
        }
        .height(this.pillBarHeight)
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width(this.totalPillBarWidth())
      .height(this.pillBarHeight)
    }
    .height(this.pillBarHeight)
    .width('100%')
  }

  build() {
    HdsNavigation(this.navStack) {
      if (this.tabBarStyle === 'pill') {
        this.PillTabsBody()
      } else {
        this.GlowTabsBody()
      }
    }
    .navDestination(pageMap)
    .hideTitleBar(true)
    .hideToolBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  GlowTabsBody() {
    HdsTabs({ controller: this.hdsTabController }) {
      TabContent() {
        FlowPage({ navStack: this.navStack })
      }
      .tabBar(new BottomTabBarStyle({
        normal: this.getTabNormalIcon(0),
        selected: this.getTabSelectedIcon(0)
      }, this.getTabLabel(0))
        .labelStyle({
          font: { size: 10, weight: FontWeight.Medium },
          unselectedColor: '#8E8E93',
          selectedColor: this.getTabColor(0)
        })
        .padding({ top: 4, bottom: 4, left: 2, right: 2 }))

      TabContent() {
        CalendarPage({ navStack: this.navStack })
      }
      .tabBar(new BottomTabBarStyle({
        normal: this.getTabNormalIcon(1),
        selected: this.getTabSelectedIcon(1)
      }, this.getTabLabel(1))
        .labelStyle({
          font: { size: 10, weight: FontWeight.Medium },
          unselectedColor: '#8E8E93',
          selectedColor: this.getTabColor(1)
        })
        .padding({ top: 4, bottom: 4, left: 2, right: 2 }))

      TabContent() {
        TaskPage({ navPathStack: this.navStack })
      }
      .tabBar(new BottomTabBarStyle({
        normal: this.getTabNormalIcon(2),
        selected: this.getTabSelectedIcon(2)
      }, this.getTabLabel(2))
        .labelStyle({
          font: { size: 10, weight: FontWeight.Medium },
          unselectedColor: '#8E8E93',
          selectedColor: this.getTabColor(2)
        })
        .padding({ top: 4, bottom: 4, left: 2, right: 2 }))

      TabContent() {
        ScholarPage({ navStack: this.navStack })
      }
      .tabBar(new BottomTabBarStyle({
        normal: this.getTabNormalIcon(3),
        selected: this.getTabSelectedIcon(3)
      }, this.getTabLabel(3))
        .labelStyle({
          font: { size: 10, weight: FontWeight.Medium },
          unselectedColor: '#8E8E93',
          selectedColor: this.getTabColor(3)
        })
        .padding({ top: 4, bottom: 4, left: 2, right: 2 }))

      TabContent() {
        OptionPage({ navStack: this.navStack })
      }
      .tabBar(new BottomTabBarStyle({
        normal: this.getTabNormalIcon(4),
        selected: this.getTabSelectedIcon(4)
      }, this.getTabLabel(4))
        .labelStyle({
          font: { size: 10, weight: FontWeight.Medium },
          unselectedColor: '#8E8E93',
          selectedColor: this.getTabColor(4)
        })
        .padding({ top: 4, bottom: 4, left: 2, right: 2 }))
    }
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barFloatingStyle({
      barBottomMargin: 28,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .onChange((index: number) => { this.currentIndex = index; })
  }

  @Builder
  PillTabsBody() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ controller: this.tabController, index: this.currentIndex }) {
        TabContent() {
          FlowPage({ navStack: this.navStack })
        }
        TabContent() {
          CalendarPage({ navStack: this.navStack })
        }
        TabContent() {
          TaskPage({ navPathStack: this.navStack })
        }
        TabContent() {
          ScholarPage({ navStack: this.navStack })
        }
        TabContent() {
          OptionPage({ navStack: this.navStack })
        }
      }
      .barHeight(0)
      .scrollable(true)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        if (index !== this.currentIndex) {
          this.snapToTab(index);
        }
      })

      Column() {
        this.PillTabBar()
      }
      .width('100%')
      .padding({ bottom: 28 + this.bottomRectHeight })
    }
    .width('100%')
    .height('100%')
  }
}

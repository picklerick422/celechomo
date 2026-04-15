// ScholarPage.ets - 学业信息主页

import { Semester, GpaInfo } from '../../model/Semester';
import { Todo, Course } from '../../model/Course';
import { AppKeys } from '../Index';
import { TwoLineCard, RoundRectangleCardWithForehead, SearchBar, EmptyView, LoadingView } from '../../components/CommonComponents';
import { fetchSemesters, fetchGrades, fetchCourseSchedule, fetchExams, fetchTodos } from '../../service/NetworkService';
import { StorageService } from '../../service/StorageService';
import common from '@ohos.app.ability.common';

interface SemesterIdParam {
  semesterId: string;
}

interface CourseScheduleParam {
  semesterId: string;
  isFirstHalf: boolean;
}

@Component
export struct ScholarPage {
  navStack: NavPathStack = new NavPathStack();
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @StorageLink(AppKeys.IS_GRS) isGrs: boolean = false;
  @StorageLink(AppKeys.HIDE_GPA) hideGpa: boolean = false;
  @StorageLink(AppKeys.IS_LOGGED_IN) @Watch('onLoginStateChanged') isLoggedIn: boolean = false;
  @StorageLink(AppKeys.LAST_UPDATE) lastUpdate: number = 0;
  @State semesterIndex: number = 0;
  @State isRefreshing: boolean = false;
  @State errorMessage: string = '';
  @State updateTimeLabel: string = '';
  @State isInitialFetchDone: boolean = false;
  @State currentSemesterDataLoaded: boolean = false;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  private storageService: StorageService | null = null;
  private updateLabelTimer: number = -1;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.storageService = new StorageService(context);
    } catch {}
    this.updateTimeLabel = this.computeUpdateLabel();
    this.updateLabelTimer = setInterval(() => {
      this.updateTimeLabel = this.computeUpdateLabel();
    }, 30000);

    // 设置初始学期索引为最新学期（边界保护）
    const semLen = (this.semesters ?? []).length;
    if (semLen > 0) {
      this.semesterIndex = semLen - 1;
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
  }

  private onLoginStateChanged(): void {
    if (this.isLoggedIn && !this.isInitialFetchDone && (this.semesters ?? []).length === 0 && !this.isRefreshing) {
      console.info('[ScholarPage] Login state changed to true, triggering data fetch...');
      this.fetchData();
    }
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

  private formatGpa(value: number): string {
    if (this.hideGpa) return '***';
    if (value <= 0) return '-';
    return value.toFixed(2);
  }

  private formatCredits(value: number): string {
    if (value <= 0) return '-';
    return value.toFixed(1);
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

  // 获取当前学期的数据（成绩、课表等）
  private async fetchCurrentSemesterData(sem: Semester): Promise<void> {
    console.info(`[ScholarPage] Fetching data for semester: ${sem.id}`);
    this.isRefreshing = true;
    this.errorMessage = '';

    try {
      const results = await Promise.all([
        fetchGrades(sem.id),
        fetchCourseSchedule(sem.id),
        fetchExams(sem.id),
        fetchTodos(sem.id)
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
      // 获取学期列表（若 HTML 解析失败会自动使用日期兜底方案）
      console.info('[ScholarPage] Fetching semesters...');
      const semResult = await fetchSemesters();
      console.info(`[ScholarPage] Semester result: success=${semResult.success}, count=${semResult.data?.length ?? 0}, msg=${semResult.message}`);

      if (!semResult.success || !semResult.data || semResult.data.length === 0) {
        this.errorMessage = semResult.message || '无法获取学期列表';
        this.isRefreshing = false;
        console.error(`[ScholarPage] Failed to fetch semesters: ${semResult.message}`);
        return;
      }

      // 使用返回的学期列表
      const candidateSemesters: Semester[] = semResult.data;
      console.info(`[ScholarPage] Got ${candidateSemesters.length} candidate semesters`);

      // 获取最近 8 个学期的数据（4 年，约 8 学期）
      // 避免一次请求太多学期导致超时，分批获取
      const semestersToFetch = candidateSemesters.slice(-8);
      console.info(`[ScholarPage] Fetching data for ${semestersToFetch.length} recent semesters`);

      for (const sem of semestersToFetch) {
        console.info(`[ScholarPage] Fetching: ${sem.id}`);
        try {
          const GeneratedDestructArray_1 = await Promise.all([
            fetchGrades(sem.id),
            fetchCourseSchedule(sem.id),
            fetchExams(sem.id),
            fetchTodos(sem.id)
          ]);
          const gradesResult =
            GeneratedDestructArray_1[0];
          const scheduleResult =
              GeneratedDestructArray_1[1];
          const examsResult =
                GeneratedDestructArray_1[2];
          const todosResult =
                  GeneratedDestructArray_1[3];

          if (gradesResult.success && gradesResult.data && gradesResult.data.length > 0) {
            sem.courses = gradesResult.data;
            console.info(`[ScholarPage] ${sem.id}: got ${gradesResult.data.length} grades`);
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
            console.info(`[ScholarPage] ${sem.id}: got ${scheduleResult.data.length} schedule courses`);
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

      // 计算当前（最新）学期的 GPA
      const currentSem = candidateSemesters[candidateSemesters.length - 1];
      if (currentSem) {
        this.computeGpa(currentSem);
        this.currentSemesterDataLoaded = true;
      }

      // 更新学期列表（默认选中最新学期）
      const updatedSemesters = candidateSemesters;

      AppStorage.set(AppKeys.SEMESTERS, updatedSemesters);
      this.semesterIndex = Math.max(0, updatedSemesters.length - 1);

      const ts = Date.now();
      AppStorage.set(AppKeys.LAST_UPDATE, ts);
      await this.storageService?.saveSemesters(updatedSemesters);

      console.info(`[ScholarPage] Data fetch completed, saved ${updatedSemesters.length} semesters`);
      this.isInitialFetchDone = true;
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
              TwoLineCard({ title: '五分制GPA', value: this.formatGpa(this.currentSemester!.gpaInfo.fivePointGpa) })
                .padding(12)
            }
            GridItem() {
              TwoLineCard({ title: '获得学分', value: this.formatCredits(this.currentSemester!.gpaInfo.totalCredits) })
                .padding(12)
            }
            GridItem() {
              TwoLineCard({ title: '四分制GPA', value: this.formatGpa(this.currentSemester!.gpaInfo.fourThreeGpa) })
                .padding(12)
            }
            GridItem() {
              TwoLineCard({ title: '主修均绩', value: this.formatGpa(this.currentSemester!.gpaInfo.majorGpa) })
                .padding(12)
            }
            GridItem() {
              TwoLineCard({ title: '主修学分', value: this.formatCredits(this.currentSemester!.gpaInfo.majorCredits) })
                .padding(12)
            }
            GridItem() {
              TwoLineCard({ title: '百分制', value: this.formatGpa(this.currentSemester!.gpaInfo.percentageGpa) })
                .padding(12)
            }
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(0)
          .rowsGap(0)
          .padding({ left: 8, right: 8, bottom: 8 })
          .onClick(() => {
            const param: Record<string, ESObject> = { "semesterIndex": this.semesterIndex } as Record<string, ESObject>;
            this.navStack.pushPathByName('GradeDetail', param);
          })

          // 成绩列表
          if (this.currentSemester!.courses.filter((c: Course) => c.hasGrade).length > 0) {
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
              const param: Record<string, ESObject> = { "semesterIndex": this.semesterIndex } as Record<string, ESObject>;
              this.navStack.pushPathByName('GradeDetail', param);
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
            this.StatCard('课程', this.currentSemester!.courses.length.toString(), () => {
              const param: SemesterIdParam = { semesterId: this.currentSemester!.id };
              this.navStack.pushPathByName('CourseList', param);
            })
            this.StatCard('学分', this.currentSemester!.gpaInfo.totalCredits.toFixed(1), () => {})
            this.StatCard('考试', this.currentSemester!.exams.length.toString(), () => {
              const param: SemesterIdParam = { semesterId: this.currentSemester!.id };
              this.navStack.pushPathByName('ExamList', param);
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
      const param: CourseScheduleParam = { semesterId: sem.id, isFirstHalf: isFirst };
      this.navStack.pushPathByName('CourseSchedule', param);
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
            this.StatCard('总计', this.currentSemester!.todos.length.toString(), () => {})
            this.StatCard('今日', this.currentSemester!.todos.filter((t: Todo) => t.dueTime <= new Date(new Date().getTime() + 86400000)).length.toString(), () => {})
            this.StatCard('本周', this.currentSemester!.todos.filter((t: Todo) => t.dueTime <= new Date(new Date().getTime() + 7 * 86400000)).length.toString(), () => {})
          }
          .padding({ left: 12, right: 12, top: 12, bottom: 8 })

          if (this.currentSemester!.todos.length > 0) {
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
          this.StatCard('二课分', this.currentSemester!.gpaInfo.secondCredit.toFixed(1), () => {})
          this.StatCard('三课分', this.currentSemester!.gpaInfo.thirdCredit.toFixed(1), () => {})
          this.StatCard('四课分', this.currentSemester!.gpaInfo.fourthCredit.toFixed(1), () => {})
        }
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      }
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
      } else if ((this.semesters.length === 0 && this.errorMessage.length === 0) || (this.isRefreshing && this.currentSemester?.courses.length === 0)) {
        // 正在加载
        Column() {
          Blank()
          LoadingView({ message: '正在加载学业数据...' })
          Blank()
        }
        .onAppear(() => {
          // 延迟执行，确保 UI 先渲染
          setTimeout(() => {
            if (!this.isInitialFetchDone && !this.isRefreshing) {
              console.info('[ScholarPage] Triggering initial data fetch...');
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
              if (this.errorMessage.length > 0 && (this.currentSemester === null || this.currentSemester.courses.length === 0)) {
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

              // 当前学期数据卡片
              if (this.currentSemester) {
                // 显示学期信息
                Row() {
                  Text(this.currentSemester.name)
                    .fontSize(15)
                    .fontColor($r('app.color.text_secondary'))
                    .fontWeight(FontWeight.Medium)
                  Blank()
                  if (this.currentSemester.courses.length === 0 && !this.isRefreshing) {
                    Text('点击刷新获取数据')
                      .fontSize(12)
                      .fontColor($r('app.color.color_blue'))
                      .onClick(() => this.fetchCurrentSemesterData(this.currentSemester!))
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
              if (this.currentSemester?.courses.length === 0 && !this.isRefreshing && this.errorMessage.length === 0) {
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
}

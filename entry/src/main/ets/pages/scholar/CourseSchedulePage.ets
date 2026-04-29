// CourseSchedulePage.ets - 课表页面

import { Semester, PERIOD_TIMES } from '../../model/Semester';
import { Course } from '../../model/Course';
import { colorFromUid } from '../../model/Period';
import { AppKeys } from '../Index';

const WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日'];
const ROW_HEIGHT_COURSE = 56;
const LABEL_PCT_COURSE = 11;
const COL_WIDTH_PCT_COURSE = (100 - LABEL_PCT_COURSE) / 7;
const PERIOD_COUNT = 13;
const PERIOD_LABELS_COURSE: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13'];

interface ScheduleCourseItemWithTeacher {
  name: string;
  location: string;
  weekDay: number;
  startPeriod: number;
  endPeriod: number;
  color: string;
  teacher: string;
}

@Component
export struct CourseSchedulePage {
  @StorageLink(AppKeys.SEMESTERS) @Watch('onSemestersChanged') semesters: Semester[] = [];
  @State semesterId: string = '';
  @State isFirstHalf: boolean = true;
  private pathStack: NavPathStack | null = null;

  // 导航参数缓存（用于应对 semesters 数据晚于页面创建到达的场景）
  private targetCourseUid: string = '';
  private targetSemesterId: string = '';
  private targetIsFirstHalf: boolean = true;
  private hasResolvedParams: boolean = false;

  // 缓存 resolveParams 找到的 semester，防止 @StorageLink 数组替换后 currentSemester 返回 null
  private resolvedSemester: Semester | null = null;
  // 缓存课程数据，作为终极后备
  private cachedCourses: Course[] = [];
  private cachedSemesterName: string = '';
  private cachedIsSpring: boolean = false;
  private cachedHalfSemesterWeeks: number = 8;

  private get currentSemester(): Semester | null {
    const arr = this.semesters ?? [];
    const targetId = String(this.semesterId ?? '').trim();
    if (targetId.length === 0) return null;

    // 方法A: map 能正确读取 id（日志已证明），用 map+indexOf 定位
    const ids = arr.map(s => String(s?.id ?? '').trim());
    const idx = ids.indexOf(targetId);
    if (idx >= 0) {
      const found = arr[idx];
      console.info(`[CourseSchedulePage] currentSemester found via map+indexOf at idx=${idx}, id=${found?.id}`);
      return found as Semester;
    }

    // 方法B: 缓存 semester
    if (this.resolvedSemester) {
      const cacheId = String(this.resolvedSemester.id ?? '').trim();
      if (cacheId === targetId) {
        console.info(`[CourseSchedulePage] currentSemester found via cache, id=${this.resolvedSemester.id}`);
        return this.resolvedSemester;
      }
    }

    // 方法C: 直接从 AppStorage 查找（同样用 map+indexOf）
    const appSems = AppStorage.get<Semester[]>(AppKeys.SEMESTERS) ?? [];
    const appIds = appSems.map(s => String(s?.id ?? '').trim());
    const appIdx = appIds.indexOf(targetId);
    if (appIdx >= 0) {
      console.info(`[CourseSchedulePage] currentSemester found via AppStorage at idx=${appIdx}`);
      return appSems[appIdx] as Semester;
    }

    // 调试
    console.warn(
      `[CourseSchedulePage] currentSemester FAILED: targetId=${targetId}, ids=[${ids.join(',')}], appIds=[${appIds.join(',')}]`
    );
    return null;
  }

  private get currentWeekLabel(): string {
    try {
      const sem = this.currentSemester;
      if (sem) {
        const week = typeof sem.currentWeek === 'function' ? sem.currentWeek(new Date()) : 0;
        if (week === undefined || week === null || week <= 0) return sem.name ?? '';
        const label = typeof sem.weekLabel === 'function' ? sem.weekLabel(week) : '';
        return `${sem.name ?? ''} · ${label ?? ''}`;
      }
      if (this.cachedSemesterName) {
        return this.cachedSemesterName;
      }
      return '';
    } catch {
      return '';
    }
  }

  /** 根据当前系统时间计算今天是周几（1-7） */
  private get todayWeekDay(): number {
    const d = new Date().getDay();
    return d === 0 ? 7 : d;
  }

  /** 判断当前时间是否在某节课的时间段内，返回对应节次（1-based）或 0 */
  private get currentPeriodIndex(): number {
    const now = new Date();
    const minutes = now.getHours() * 60 + now.getMinutes();
    for (let i = 0; i < PERIOD_TIMES.length; i++) {
      const start = PERIOD_TIMES[i][0];
      const end = PERIOD_TIMES[i][1];
      if (minutes >= start && minutes <= end) {
        return i + 1;
      }
    }
    return 0;
  }

  /** 计算当前时间指示线的 Y 偏移（相对于 Stack 顶部） */
  private get currentTimeLineY(): number {
    const now = new Date();
    const minutes = now.getHours() * 60 + now.getMinutes();

    for (let i = 0; i < PERIOD_TIMES.length; i++) {
      const start = PERIOD_TIMES[i][0];
      const end = PERIOD_TIMES[i][1];
      if (minutes >= start && minutes <= end) {
        const progress = (minutes - start) / (end - start);
        return i * ROW_HEIGHT_COURSE + progress * ROW_HEIGHT_COURSE;
      }
      if (i < PERIOD_TIMES.length - 1) {
        const nextStart = PERIOD_TIMES[i + 1][0];
        if (minutes > end && minutes < nextStart) {
          return (i + 1) * ROW_HEIGHT_COURSE;
        }
      }
    }
    if (minutes < PERIOD_TIMES[0][0]) return 0;
    return PERIOD_COUNT * ROW_HEIGHT_COURSE;
  }

  private buildScheduleItems(courses: Course[]): ScheduleCourseItemWithTeacher[] {
    const result: ScheduleCourseItemWithTeacher[] = [];
    for (const course of (courses ?? [])) {
      if (!course) continue;
      const color = colorFromUid(course.uid ?? '');
      for (const slot of (course.timeSlots ?? [])) {
        if (!slot) continue;
        if (slot.halfType === 'first' && !this.isFirstHalf) continue;
        if (slot.halfType === 'second' && this.isFirstHalf) continue;
        result.push({
          name: course.shortName || (course.name ? course.name.slice(0, 6) : ''),
          location: slot.location || '',
          weekDay: slot.weekDay ?? 1,
          startPeriod: slot.startPeriod ?? 1,
          endPeriod: slot.endPeriod ?? 1,
          color,
          teacher: course.teacher || ''
        });
      }
    }
    return result;
  }

  private getScheduleCourses(): ScheduleCourseItemWithTeacher[] {
    try {
      const targetId = String(this.semesterId ?? '').trim();
      const arr = this.semesters ?? [];
      const arrIds = arr.map(s => s?.id ?? 'undef').join(',');

      // 直接在 getScheduleCourses 内部查找 semester，不再依赖 currentSemester getter
      let sem: Semester | null = null;

      // 方法1: map+indexOf（日志证明 map 能正确读取 id）
      const ids = arr.map(s => String(s?.id ?? '').trim());
      const idx = ids.indexOf(targetId);
      if (idx >= 0) {
        sem = arr[idx] as Semester;
        console.info(`[CourseSchedulePage] getScheduleCourses: found sem via map+indexOf at idx=${idx}, id=${sem?.id}`);
      }

      // 方法2: 缓存 semester
      if (!sem && this.resolvedSemester) {
        const cacheId = String(this.resolvedSemester.id ?? '').trim();
        if (cacheId === targetId) {
          sem = this.resolvedSemester;
          console.info(`[CourseSchedulePage] getScheduleCourses: found sem via cache, id=${sem?.id}`);
        }
      }

      // 方法3: AppStorage
      if (!sem) {
        const appSems = AppStorage.get<Semester[]>(AppKeys.SEMESTERS) ?? [];
        const appIds = appSems.map(s => String(s?.id ?? '').trim());
        const appIdx = appIds.indexOf(targetId);
        if (appIdx >= 0) {
          sem = appSems[appIdx] as Semester;
          console.info(`[CourseSchedulePage] getScheduleCourses: found sem via AppStorage at idx=${appIdx}`);
        }
      }

      console.info(
        `[CourseSchedulePage] getScheduleCourses: semId=${sem?.id ?? 'null'}, ` +
        `targetSemId=${targetId}, arrIds=[${arrIds}], isFirstHalf=${this.isFirstHalf}`
      );

      if (sem) {
        const result = this.buildScheduleItems(sem.courses ?? []);
        console.info(`[CourseSchedulePage] getScheduleCourses: returning ${result.length} courses from sem`);
        return result;
      }

      // 终极后备：使用 resolveParams 时缓存的课程数据
      if (this.cachedCourses.length > 0 && String(this.resolvedSemester?.id ?? '').trim() === targetId) {
        const result = this.buildScheduleItems(this.cachedCourses);
        console.info(`[CourseSchedulePage] getScheduleCourses: using cached ${result.length} courses`);
        return result;
      }

      console.warn(`[CourseSchedulePage] getScheduleCourses: no semester found for targetId=${targetId}`);
      return [];
    } catch (e) {
      console.error(`[CourseSchedulePage] getScheduleCourses error: ${(e as Error).message}`);
      return [];
    }
  }

  /** 获取当前学期的半学期标签 */
  private getHalfSemesterLabels(): [string, string] {
    const sem = this.currentSemester;
    if (sem) {
      if (sem.isSpring) return ['春学期', '夏学期'];
      return ['秋学期', '冬学期'];
    }
    if (this.cachedIsSpring) return ['春学期', '夏学期'];
    return ['前半学期', '后半学期'];
  }

  private formatPeriodTime(idx: number): string {
    const time = PERIOD_TIMES[idx];
    if (!time) return '';
    const h = Math.floor(time[0] / 60);
    const m = time[0] % 60;
    return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}`;
  }

  /** 当 semesters 数据变化时重新尝试解析导航参数 */
  private onSemestersChanged(): void {
    if (!this.hasResolvedParams) {
      this.resolveParams();
    }
  }

  /** 解析导航参数，将 courseUid / semesterId 转换为实际 semesterId */
  private resolveParams(): void {
    if (this.hasResolvedParams) {
      console.info(`[CourseSchedulePage] resolveParams skipped: already resolved`);
      return;
    }

    if (this.targetCourseUid) {
      console.info(`[CourseSchedulePage] resolving by courseUid=${this.targetCourseUid}`);
      for (const sem of (this.semesters ?? [])) {
        const course = (sem.courses ?? []).find(c => c.uid === this.targetCourseUid);
        if (course) {
          this.semesterId = sem.id;
          this.resolvedSemester = sem;
          // 缓存课程数据，防止后续 @StorageLink 数组替换后无法找到 semester
          this.cachedCourses = sem.courses ?? [];
          this.cachedSemesterName = sem.name ?? '';
          this.cachedIsSpring = sem.isSpring ?? false;
          this.cachedHalfSemesterWeeks = sem.halfSemesterWeeks ?? 8;
          // 根据当前日期判断所在半学期，而不是课程是否包含某个半学期
          const week = typeof sem.currentWeek === 'function' ? sem.currentWeek(new Date()) : 0;
          if (week > 0) {
            this.isFirstHalf = week <= (sem.halfSemesterWeeks ?? 8);
          } else {
            const hasFirst = course.timeSlots?.some(s => s.halfType === 'first' || s.halfType === 'full') ?? false;
            const hasSecond = course.timeSlots?.some(s => s.halfType === 'second' || s.halfType === 'full') ?? false;
            this.isFirstHalf = hasFirst || !hasSecond;
          }
          this.hasResolvedParams = true;
          console.info(`[CourseSchedulePage] found course in sem=${sem.id}, week=${week}, isFirstHalf=${this.isFirstHalf}, cachedCourses=${this.cachedCourses.length}`);
          return;
        }
      }
      console.warn(`[CourseSchedulePage] courseUid not found in any semester, will fallback`);
    } else {
      this.semesterId = this.targetSemesterId;
      this.isFirstHalf = this.targetIsFirstHalf;
      this.hasResolvedParams = true;
      console.info(`[CourseSchedulePage] resolved by semesterId=${this.semesterId}`);
      return;
    }

    // 若传了 courseUid 但未找到，且 semesters 已加载完成，则 fallback 到当前学期
    if (this.targetCourseUid && (this.semesters ?? []).length > 0) {
      console.warn(`[CourseSchedulePage] falling back to current semester`);
      this.fallbackToCurrentSemester();
      this.hasResolvedParams = true;
    }
  }

  /** 回退到包含当前日期的学期 */
  private fallbackToCurrentSemester(): void {
    const now = new Date();
    for (const sem of (this.semesters ?? [])) {
      if (now >= sem.startDate && now <= sem.endDate) {
        this.semesterId = sem.id;
        this.resolvedSemester = sem;
        this.cachedCourses = sem.courses ?? [];
        this.cachedSemesterName = sem.name ?? '';
        this.cachedIsSpring = sem.isSpring ?? false;
        this.cachedHalfSemesterWeeks = sem.halfSemesterWeeks ?? 8;
        const week = typeof sem.currentWeek === 'function' ? sem.currentWeek(now) : 0;
        if (week > 0) {
          this.isFirstHalf = week <= (sem.halfSemesterWeeks ?? 8);
        }
        console.info(`[CourseSchedulePage] fallback to current sem=${sem.id}, week=${week}, isFirstHalf=${this.isFirstHalf}`);
        break;
      }
    }
    if (!this.semesterId && (this.semesters ?? []).length > 0) {
      const firstSem = this.semesters[0];
      this.semesterId = firstSem?.id ?? '';
      this.resolvedSemester = firstSem ?? null;
      this.cachedCourses = firstSem?.courses ?? [];
      this.cachedSemesterName = firstSem?.name ?? '';
      this.cachedIsSpring = firstSem?.isSpring ?? false;
      this.cachedHalfSemesterWeeks = firstSem?.halfSemesterWeeks ?? 8;
      console.info(`[CourseSchedulePage] fallback to first sem=${this.semesterId}`);
    }
  }

  build() {
    NavDestination() {
      Column() {
        // ===== 导航栏 =====
        Row() {
          Button({ type: ButtonType.Normal }) {
            Image($r('sys.media.ohos_ic_public_arrow_left'))
              .width(22).height(22).fillColor($r('app.color.color_blue'))
          }
          .backgroundColor(Color.Transparent).padding(8)
          .onClick(() => this.pathStack?.pop())

          Column({ space: 2 }) {
            Text('课表')
              .fontSize(17).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            if ((this.currentWeekLabel ?? '').length > 0) {
              Text(this.currentWeekLabel)
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)

          Row().width(46)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        // ===== 前/后半学期切换 =====
        Row({ space: 8 }) {
          Text(this.getHalfSemesterLabels()[0])
            .fontSize(13)
            .fontColor(this.isFirstHalf ? Color.White : $r('app.color.text_secondary'))
            .fontWeight(this.isFirstHalf ? FontWeight.Medium : FontWeight.Regular)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(this.isFirstHalf ? $r('app.color.color_blue') : $r('app.color.progress_bg'))
            .onClick(() => { this.isFirstHalf = true; })

          Text(this.getHalfSemesterLabels()[1])
            .fontSize(13)
            .fontColor(!this.isFirstHalf ? Color.White : $r('app.color.text_secondary'))
            .fontWeight(!this.isFirstHalf ? FontWeight.Medium : FontWeight.Regular)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(!this.isFirstHalf ? $r('app.color.color_blue') : $r('app.color.progress_bg'))
            .onClick(() => { this.isFirstHalf = false; })
        }
        .padding({ left: 16, top: 10, bottom: 6 })
        .width('100%')

        // ===== 表头 =====
        Row() {
          Text('')
            .width(`${LABEL_PCT_COURSE}%`)
            .textAlign(TextAlign.Center)

          ForEach(WEEKDAYS, (day: string, idx: number) => {
            Column({ space: 2 }) {
              Text(day)
                .fontSize(13)
                .fontColor((idx + 1) === this.todayWeekDay ? $r('app.color.color_blue') : $r('app.color.text_secondary'))
                .fontWeight((idx + 1) === this.todayWeekDay ? FontWeight.Bold : FontWeight.Regular)
              if ((idx + 1) === this.todayWeekDay) {
                Row()
                  .width(4).height(4).borderRadius(2)
                  .backgroundColor($r('app.color.color_blue'))
              }
            }
            .layoutWeight(1)
            .height(36)
            .justifyContent(FlexAlign.Center)
          }, (day: string, idx: number) => `${day}-${idx}`)
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 4 })

        // ===== 课表主体或空状态 =====
        if (this.getScheduleCourses().length === 0) {
          Column({ space: 8 }) {
            Text('📖')
              .fontSize(48)
            Text('暂无课程')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
              .fontWeight(FontWeight.Medium)
            Text(this.semesterId ? '该半学期暂无课程安排' : '请稍后，正在加载课程数据...')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Stack({ alignContent: Alignment.TopStart }) {
              // --- 背景格子 ---
              Column() {
                ForEach(PERIOD_LABELS_COURSE, (label: string, idx: number) => {
                  Row() {
                    Column() {
                      Text(label)
                        .fontSize(11)
                        .fontColor((idx + 1) === this.currentPeriodIndex ? $r('app.color.color_blue') : $r('app.color.text_tertiary'))
                        .fontWeight((idx + 1) === this.currentPeriodIndex ? FontWeight.Medium : FontWeight.Regular)
                        .textAlign(TextAlign.Center)
                      Text(this.formatPeriodTime(idx))
                        .fontSize(9)
                        .fontColor((idx + 1) === this.currentPeriodIndex ? $r('app.color.color_blue') : $r('app.color.text_tertiary'))
                        .textAlign(TextAlign.Center)
                    }
                    .width(`${LABEL_PCT_COURSE}%`)
                    .height(ROW_HEIGHT_COURSE)
                    .justifyContent(FlexAlign.Center)

                    ForEach(WEEKDAYS, (_: string, widx: number) => {
                      Row()
                        .layoutWeight(1)
                        .height(ROW_HEIGHT_COURSE)
                        .backgroundColor((widx + 1) === this.todayWeekDay ? $r('app.color.selected_day_bg') : Color.Transparent)
                        .border({
                          width: { left: 0.5, bottom: 0.5 },
                          color: $r('app.color.separator'),
                          style: BorderStyle.Solid
                        })
                    }, (_: string, widx: number) => `${widx}`)
                  }
                  .width('100%')
                }, (label: string, idx: number) => `${label}-${idx}`)
              }
              .width('100%')

              // --- 当前时间指示线 ---
              if (this.currentPeriodIndex > 0) {
                Row() {
                  Row()
                    .width(`${LABEL_PCT_COURSE}%`)
                    .height('100%')
                  Row()
                    .layoutWeight(1)
                    .height('100%')
                    .backgroundColor('#1AFF3B30')
                }
                .width('100%')
                .height(2)
                .backgroundColor('#FF3B30')
                .position({ x: 0, y: this.currentTimeLineY - 1 })
                .zIndex(5)

                Row()
                  .width(6).height(6).borderRadius(3)
                  .backgroundColor('#FF3B30')
                  .position({ x: `${LABEL_PCT_COURSE - 1.5}%`, y: this.currentTimeLineY - 3 })
                  .zIndex(6)
              }

              // --- 课程卡片 ---
              ForEach(this.getScheduleCourses(), (course: ScheduleCourseItemWithTeacher) => {
                this.CourseBlock(course)
              }, (c: ScheduleCourseItemWithTeacher) => `${c.weekDay}-${c.startPeriod}-${c.name}`)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as Record<string, string | boolean>;
      console.info(`[CourseSchedulePage] onReady called, params=${JSON.stringify(params)}`);

      const courseUid = params?.['courseUid'] as string;
      if (courseUid) {
        this.targetCourseUid = courseUid;
      } else {
        this.targetSemesterId = (params?.['semesterId'] as string) ?? '';
        const rawIsFirstHalf = params?.['isFirstHalf'];
        this.targetIsFirstHalf = rawIsFirstHalf === true || rawIsFirstHalf === 'true';
      }
      console.info(`[CourseSchedulePage] targetCourseUid=${this.targetCourseUid}, targetSemesterId=${this.targetSemesterId}, semestersCount=${(this.semesters ?? []).length}`);
      this.resolveParams();
      console.info(`[CourseSchedulePage] after resolveParams: semesterId=${this.semesterId}, isFirstHalf=${this.isFirstHalf}, hasResolved=${this.hasResolvedParams}`);
    })
  }

  @Builder
  CourseBlock(course: ScheduleCourseItemWithTeacher) {
    Column({ space: 2 }) {
      Text(course.name)
        .fontSize(11)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)

      if (course.location && course.location.length > 0) {
        Text(course.location)
          .fontSize(9)
          .fontColor(Color.White)
          .opacity(0.9)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
      }

      if (course.teacher && course.teacher.length > 0) {
        Text(course.teacher)
          .fontSize(9)
          .fontColor(Color.White)
          .opacity(0.75)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width(`${COL_WIDTH_PCT_COURSE - 1.2}%`)
    .height((course.endPeriod - course.startPeriod + 1) * ROW_HEIGHT_COURSE - 4)
    .borderRadius(8)
    .backgroundColor(course.color)
    .padding(4)
    .clip(true)
    .shadow({
      radius: 6,
      color: course.color + '66',
      offsetX: 0,
      offsetY: 2
    })
    .position({
      x: `${LABEL_PCT_COURSE + (course.weekDay - 1) * COL_WIDTH_PCT_COURSE + 0.6}%`,
      y: (course.startPeriod - 1) * ROW_HEIGHT_COURSE + 2
    })
    .zIndex(2)
  }
}

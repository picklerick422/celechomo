// CalendarPage.ets - 日程页面（日历视图 + 课表视图）

import { Period, PeriodType, colorFromUid } from '../../model/Period';
import { Semester, PERIOD_TIMES } from '../../model/Semester';
import { CourseTimeSlot } from '../../model/Course';
import { AppKeys } from '../Index';
import { EmptyView } from '../../components/CommonComponents';

type CalendarFormat = 'month' | 'week';
type ViewMode = 'calendar' | 'schedule';

interface ScheduleCourseItem {
  name: string;
  location: string;
  weekDay: number;
  startPeriod: number;
  endPeriod: number;
  color: string;
}

interface MergedSlot {
  startPeriod: number;
  endPeriod: number;
  location: string;
}

const WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日'];
const MONTHS = ['1月', '2月', '3月', '4月', '5月', '6月',
  '7月', '8月', '9月', '10月', '11月', '12月'];
const PERIOD_LABELS: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13'];
const ROW_HEIGHT: number = 48;
const LABEL_PCT: number = 9.5;
const COL_WIDTH_PCT: number = (100 - LABEL_PCT) / 7;

@Component
export struct CalendarPage {
  navStack: NavPathStack = new NavPathStack();
  @StorageLink(AppKeys.FLOW_LIST) flowList: Period[] = [];
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @State selectedDay: Date = new Date();
  @State focusedMonth: Date = new Date();
  @State calendarFormat: CalendarFormat = 'month';
  @State viewMode: ViewMode = 'calendar';
  @State isFirstHalf: boolean = true;
  @State isRefreshing: boolean = false;
  @State isSwipeHandled: boolean = false;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;

  aboutToAppear(): void {
    const today = new Date();
    this.selectedDay = today;
    this.focusedMonth = today;
  }

  // ============= 日历计算 =============

  /** 获取月历所有格子（前补+本月+后补） */
  private getMonthCells(): Date[] {
    const year = this.focusedMonth.getFullYear();
    const month = this.focusedMonth.getMonth();
    const firstDay = new Date(year, month, 1);
    const lastDay = new Date(year, month + 1, 0);

    let startOffset = firstDay.getDay() - 1;
    if (startOffset < 0) startOffset = 6;

    const cells: Date[] = [];
    for (let i = startOffset; i > 0; i--) {
      cells.push(new Date(year, month, 1 - i));
    }
    for (let d = 1; d <= lastDay.getDate(); d++) {
      cells.push(new Date(year, month, d));
    }
    while (cells.length % 7 !== 0) {
      cells.push(new Date(year, month + 1, cells.length - lastDay.getDate() - startOffset + 1));
    }
    return cells;
  }

  /** 获取本周日历格子 */
  private getWeekCells(): Date[] {
    const day = this.selectedDay.getDay();
    const offset = day === 0 ? -6 : 1 - day;
    const monday = new Date(this.selectedDay);
    monday.setDate(this.selectedDay.getDate() + offset);
    const cells: Date[] = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(monday);
      d.setDate(monday.getDate() + i);
      cells.push(d);
    }
    return cells;
  }

  /** 安全获取 Date 对象（处理 PersistentStorage 恢复后的字符串日期） */
  private safeDate(d: Date | string): Date {
    return d instanceof Date ? d : new Date(d as string);
  }

  /** 直接从 semesters 获取某天的所有事件（支持历史日期，周次计算与 FlowService 一致） */
  private getDayPeriods(date: Date): Period[] {
    const periods: Period[] = [];
    const weekday = date.getDay() === 0 ? 7 : date.getDay(); // 1=周一 ... 7=周日

    for (const sem of this.semesters) {
      // 安全转换日期（PersistentStorage 恢复后可能是字符串）
      const startDate = this.safeDate(sem.startDate);
      const endDate = this.safeDate(sem.endDate);

      // 计算学期第一周周一（与 FlowService 一致）
      const semDay = startDate.getDay();
      const semOffset = semDay === 0 ? -6 : 1 - semDay;
      const semWeek1Monday = new Date(startDate.getFullYear(), startDate.getMonth(),
        startDate.getDate() + semOffset);

      // 计算日期所在周的周一
      const dateDay = date.getDay();
      const dateOffset = dateDay === 0 ? -6 : 1 - dateDay;
      const dateMonday = new Date(date.getFullYear(), date.getMonth(), date.getDate() + dateOffset);

      // 计算当前是第几周
      const weekDiff = Math.floor((dateMonday.getTime() - semWeek1Monday.getTime()) / (7 * 86400000)) + 1;

      // 学期时间范围（±14天宽限）
      const semStart = new Date(startDate.getTime() - 14 * 86400000);
      const semEnd = new Date(endDate.getTime() + 14 * 86400000);
      const inSemesterRange = date >= semStart && date <= semEnd;
      const validWeek = weekDiff > 0;

      // 判断当前日期属于前半学期还是后半学期
      const isDateInFirstHalf = weekDiff <= sem.firstHalfWeeks;

      // 课程（需同时满足学期范围、有效周次、半学期匹配）
      if (inSemesterRange && validWeek) {
        for (const course of (sem.courses ?? [])) {
          // 收集该课程当天所有匹配的 timeSlots
          const matchedSlots: CourseTimeSlot[] = [];
          for (const slot of (course.timeSlots ?? [])) {
            // 半学期过滤（只过滤当 isFirstHalf 为 boolean 时）
            if (typeof slot.isFirstHalf === 'boolean' && slot.isFirstHalf !== isDateInFirstHalf) {
              continue;
            }
            const weeks = Array.isArray(slot.weeks) ? slot.weeks : [];
            if (weeks.includes(weekDiff) && slot.weekDay === weekday) {
              matchedSlots.push(slot);
            }
          }

          if (matchedSlots.length === 0) continue;

          // 按 startPeriod 排序
          matchedSlots.sort((a, b) => a.startPeriod - b.startPeriod);

          // 合并相邻的 timeSlot
          const merged: MergedSlot[] = [];
          let current: MergedSlot = {
            startPeriod: matchedSlots[0].startPeriod,
            endPeriod: matchedSlots[0].endPeriod,
            location: matchedSlots[0].location
          };
          for (let i = 1; i < matchedSlots.length; i++) {
            const slot = matchedSlots[i];
            if (slot.startPeriod === current.endPeriod + 1) {
              // 相邻，合并
              current.endPeriod = slot.endPeriod;
              if (!current.location && slot.location) current.location = slot.location;
            } else {
              merged.push(current);
              current = {
                startPeriod: slot.startPeriod,
                endPeriod: slot.endPeriod,
                location: slot.location
              };
            }
          }
          merged.push(current);

          // 为每个合并后的 slot 生成 Period
          for (const m of merged) {
            const startMinutes = PERIOD_TIMES[m.startPeriod - 1]?.[0] ?? 480;
            const endMinutes = PERIOD_TIMES[m.endPeriod - 1]?.[1] ?? 525;
            const startTime = new Date(date.getFullYear(), date.getMonth(), date.getDate(),
              Math.floor(startMinutes / 60), startMinutes % 60);
            const endTime = new Date(date.getFullYear(), date.getMonth(), date.getDate(),
              Math.floor(endMinutes / 60), endMinutes % 60);
            periods.push(new Period(
              `cls_${course.uid}_w${weekDiff}_d${weekday}_p${m.startPeriod}`,
              course.name, startTime, endTime,
              PeriodType.CLASSES, m.location, course.uid
            ));
          }
        }
      }

      // 考试（不受学期日期限制，只匹配日期；安全转换日期）
      for (const exam of sem.exams) {
        const examStart = this.safeDate(exam.startTime);
        if (this.isSameDay(examStart, date)) {
          periods.push(new Period(
            `exam_${exam.uid}`,
            `${exam.courseName} 考试`,
            examStart, this.safeDate(exam.endTime),
            PeriodType.TEST, exam.location, exam.uid
          ));
        }
      }
    }

    // 合并 flowList 中的用户自定义任务（排除已由 semesters 生成的课程/考试，避免重复）
    const flowEvents = this.flowList.filter(p => {
      const d = p.startTime;
      return p.type === PeriodType.USER &&
        d.getFullYear() === date.getFullYear() &&
        d.getMonth() === date.getMonth() &&
        d.getDate() === date.getDate();
    });
    periods.push(...flowEvents);

    return periods.sort((a, b) => a.startTime.getTime() - b.startTime.getTime());
  }

  /** 获取某天的前 N 个事件，用于日历标记 */
  private getDayEventMarkers(date: Date): Period[] {
    return this.getDayPeriods(date).slice(0, 3);
  }

  private isSameDay(a: Date, b: Date): boolean {
    return a.getFullYear() === b.getFullYear() &&
      a.getMonth() === b.getMonth() &&
      a.getDate() === b.getDate();
  }

  private isToday(date: Date): boolean {
    return this.isSameDay(date, new Date());
  }

  private isCurrentMonth(date: Date): boolean {
    return date.getMonth() === this.focusedMonth.getMonth() &&
      date.getFullYear() === this.focusedMonth.getFullYear();
  }

  private goToToday(): void {
    const today = new Date();
    this.selectedDay = today;
    this.focusedMonth = today;
  }

  private prevMonth(): void {
    this.focusedMonth = new Date(this.focusedMonth.getFullYear(),
      this.focusedMonth.getMonth() - 1, 1);
  }

  private nextMonth(): void {
    this.focusedMonth = new Date(this.focusedMonth.getFullYear(),
      this.focusedMonth.getMonth() + 1, 1);
  }

  private prevWeek(): void {
    this.selectedDay = new Date(this.selectedDay.getTime() - 7 * 86400000);
  }

  private nextWeek(): void {
    this.selectedDay = new Date(this.selectedDay.getTime() + 7 * 86400000);
  }

  private getPeriodColor(period: Period): string {
    switch (period.type) {
      case PeriodType.TEST: return '#F48FB1';
      case PeriodType.CLASSES: return colorFromUid(period.fromUid || period.uid);
      default: return colorFromUid(period.fromUid || period.uid);
    }
  }

  private formatEventTime(period: Period): string {
    const fmtTime = (d: Date) =>
      `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
    return `${fmtTime(period.startTime)} - ${fmtTime(period.endTime)}`;
  }

  private getEventTypeLabel(period: Period): string {
    switch (period.type) {
      case PeriodType.TEST: return '考试';
      case PeriodType.CLASSES: return '课程';
      default: return '任务';
    }
  }

  private getEventTypeColor(period: Period): string {
    switch (period.type) {
      case PeriodType.TEST: return '#F48FB1';
      case PeriodType.CLASSES: return '#2196F3';
      default: return '#4CAF50';
    }
  }

  private getEventTypeBg(period: Period): string {
    switch (period.type) {
      case PeriodType.TEST: return '#FCE4EC';
      case PeriodType.CLASSES: return '#E3F2FD';
      default: return '#E8F5E9';
    }
  }

  // ============= 课表视图 =============

  private getCurrentSemester(): Semester | null {
    const now = new Date();
    for (const s of this.semesters) {
      const sStart = this.safeDate(s.startDate);
      const sEnd = this.safeDate(s.endDate);
      if (sStart <= now && now <= sEnd) return s;
    }
    return this.semesters.length > 0 ? this.semesters[this.semesters.length - 1] : null;
  }

  private getScheduleCourses(): ScheduleCourseItem[] {
    const semester = this.getCurrentSemester();
    if (!semester) return [];
    const now = new Date();
    const week = semester.currentWeek(now);
    const result: ScheduleCourseItem[] = [];

    for (const course of semester.courses) {
      const courseColor = colorFromUid(course.uid);
      for (const slot of course.timeSlots) {
        if (slot.isFirstHalf !== this.isFirstHalf) continue;
        if (week > 0 && !slot.weeks.includes(week)) continue;
        const item: ScheduleCourseItem = {
          name: course.shortName || course.name.slice(0, 6),
          location: slot.location,
          weekDay: slot.weekDay,
          startPeriod: slot.startPeriod,
          endPeriod: slot.endPeriod,
          color: courseColor
        };
        result.push(item);
      }
    }
    return result;
  }

  // ============= UI 构建 =============

  @Builder
  CalendarHeader() {
    Row() {
      if (this.calendarFormat === 'month') {
        Button({ type: ButtonType.Circle }) {
          Image($r('sys.media.ohos_ic_public_arrow_left'))
            .width(16).height(16)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(32).height(32)
        .backgroundColor($r('app.color.progress_bg'))
        .onClick(() => this.prevMonth())
      }

      Text(this.calendarFormat === 'month' ?
        `${this.focusedMonth.getFullYear()}年${MONTHS[this.focusedMonth.getMonth()]}` :
        this.getWeekRangeLabel()
      )
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(this.calendarFormat === 'month' ? TextAlign.Center : TextAlign.Start)

      if (this.calendarFormat === 'month') {
        Button({ type: ButtonType.Circle }) {
          Image($r('sys.media.ohos_ic_public_arrow_right'))
            .width(16).height(16)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(32).height(32)
        .backgroundColor($r('app.color.progress_bg'))
        .onClick(() => this.nextMonth())
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 4 })
  }

  private getWeekRangeLabel(): string {
    const cells = this.getWeekCells();
    if (cells.length === 0) return '';
    const first = cells[0];
    const last = cells[6];
    if (first.getMonth() === last.getMonth()) {
      return `${first.getFullYear()}年${MONTHS[first.getMonth()]} ${first.getDate()}-${last.getDate()}日`;
    }
    return `${MONTHS[first.getMonth()]}${first.getDate()}日 - ${MONTHS[last.getMonth()]}${last.getDate()}日`;
  }

  @Builder
  WeekDayHeader() {
    Row() {
      ForEach(WEEKDAYS, (day: string) => {
        Text(day)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('14.28%')
          .textAlign(TextAlign.Center)
          .padding({ bottom: 6 })
      })
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
  }

  @Builder
  MonthGrid() {
    Grid() {
      ForEach(this.getMonthCells(), (date: Date) => {
        GridItem() {
          this.DayCell(date)
        }
      }, (date: Date) => `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`)
    }
    .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
    .columnsGap(0)
    .rowsGap(2)
    .padding({ left: 8, right: 8 })
  }

  @Builder
  WeekRow() {
    Row() {
      ForEach(this.getWeekCells(), (date: Date) => {
        this.DayCell(date)
      }, (date: Date) => `week-${date.getDate()}`)
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
  }

  @Builder
  DayCell(date: Date) {
    Column({ space: 2 }) {
      Text(date.getDate().toString())
        .fontSize(15)
        .fontColor(
          this.isSameDay(date, this.selectedDay) ? Color.White :
            !this.isCurrentMonth(date) ? $r('app.color.text_tertiary') :
              $r('app.color.text_primary')
        )
        .width(36)
        .height(36)
        .borderRadius(18)
        .textAlign(TextAlign.Center)
        .backgroundColor(
          this.isSameDay(date, this.selectedDay) ? $r('app.color.color_blue') :
            this.isToday(date) ? $r('app.color.today_bg') :
              Color.Transparent
        )
        .fontWeight(this.isToday(date) || this.isSameDay(date, this.selectedDay) ? 600 : FontWeight.Regular)
        .shadow(this.isSameDay(date, this.selectedDay) ? {
          radius: 8,
          color: '#30007AFF',
          offsetX: 0,
          offsetY: 2
        } : {
          radius: 0,
          color: '#00000000',
          offsetX: 0,
          offsetY: 0
        })

      // 事件标记（课程=彩色圆点，考试=彩色方块）
      Row({ space: 2 }) {
        ForEach(this.getDayEventMarkers(date), (period: Period) => {
          if (period.type === PeriodType.TEST) {
            Row()
              .width(5)
              .height(5)
              .borderRadius(1.5)
              .backgroundColor(this.getPeriodColor(period))
          } else {
            Row()
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor(this.getPeriodColor(period))
          }
        }, (period: Period) => period.uid)
      }
      .height(5)
      .justifyContent(FlexAlign.Center)
    }
    .width('14.28%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 4, bottom: 4 })
    .onClick(() => {
      this.selectedDay = date;
      if (!this.isCurrentMonth(date)) {
        this.focusedMonth = date;
      }
    })
  }

  /** 日程卡片 - 与 ScholarPage CourseListItem 风格保持一致 */
  @Builder
  EventCard(period: Period) {
    Row({ space: 12 }) {
      // 左侧圆形色块（事件首字）
      Column() {
        Text(period.summary.length > 0 ? period.summary.substring(0, 1) : '?')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .backgroundColor(this.getPeriodColor(period))
      .justifyContent(FlexAlign.Center)

      // 中间内容
      Column({ space: 3 }) {
        Text(period.summary)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          Text(this.formatEventTime(period))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (period.location.length > 0) {
            Text(period.location)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(this.getEventTypeLabel(period))
            .fontSize(10)
            .fontColor(this.getEventTypeColor(period))
            .padding({ left: 4, right: 4 })
            .backgroundColor(this.getEventTypeBg(period))
            .borderRadius(4)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }

  @Builder
  ScheduleGrid() {
    Column() {
      Row({ space: 8 }) {
        Text('前半学期')
          .fontSize(13)
          .fontColor(this.isFirstHalf ? $r('app.color.color_blue') : $r('app.color.text_secondary'))
          .fontWeight(this.isFirstHalf ? FontWeight.Medium : FontWeight.Regular)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.isFirstHalf ? $r('app.color.selected_day_bg') : Color.Transparent)
          .onClick(() => { this.isFirstHalf = true; })

        Text('后半学期')
          .fontSize(13)
          .fontColor(!this.isFirstHalf ? $r('app.color.color_blue') : $r('app.color.text_secondary'))
          .fontWeight(!this.isFirstHalf ? FontWeight.Medium : FontWeight.Regular)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(!this.isFirstHalf ? $r('app.color.selected_day_bg') : Color.Transparent)
          .onClick(() => { this.isFirstHalf = false; })
      }
      .padding({ left: 16, top: 8, bottom: 8 })

      Row() {
        Text('').width(36)
        ForEach(WEEKDAYS, (day: string) => {
          Text(day)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        })
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 4 })

      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            ForEach(PERIOD_LABELS, (label: string, idx: number) => {
              Row() {
                Text(label)
                  .width(36)
                  .fontSize(10)
                  .fontColor($r('app.color.text_tertiary'))
                  .textAlign(TextAlign.Center)
                  .height(ROW_HEIGHT)

                ForEach(WEEKDAYS, (_: string) => {
                  Row()
                    .layoutWeight(1)
                    .height(ROW_HEIGHT)
                    .border({
                      width: { left: 0.5 },
                      color: $r('app.color.separator'),
                      style: BorderStyle.Dashed
                    })
                })
              }
              .width('100%')
              .border({
                width: { bottom: 0.5 },
                color: $r('app.color.separator'),
                style: BorderStyle.Dashed
              })
            })
          }

          ForEach(this.getScheduleCourses(), (course: ScheduleCourseItem) => {
            this.CourseCard(course, ROW_HEIGHT)
          }, (c: ScheduleCourseItem) => `${c.weekDay}-${c.startPeriod}`)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .layoutWeight(1)
  }

  @Builder
  CourseCard(course: ScheduleCourseItem, rowHeight: number) {
    Column({ space: 2 }) {
      Text(course.name)
        .fontSize(10)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (course.location.length > 0) {
        Text(course.location)
          .fontSize(9)
          .fontColor(Color.White)
          .opacity(0.85)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .padding(4)
    .width(`${COL_WIDTH_PCT}%`)
    .height((course.endPeriod - course.startPeriod + 1) * rowHeight - 2)
    .borderRadius(6)
    .backgroundColor(course.color)
    .position({ x: `${LABEL_PCT + (course.weekDay - 1) * COL_WIDTH_PCT}%`, y: (course.startPeriod - 1) * rowHeight })
    .clip(true)
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Column({ space: 4 }) {
          Text(this.viewMode === 'calendar' ?
            `${this.focusedMonth.getFullYear()}年${MONTHS[this.focusedMonth.getMonth()]}` :
            '课表'
          )
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          if (this.viewMode === 'calendar') {
            Text(this.isToday(this.selectedDay) ? '今天' :
              `${this.selectedDay.getMonth() + 1}月${this.selectedDay.getDate()}日`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        if (this.viewMode === 'calendar') {
          Button(this.calendarFormat === 'month' ? '周' : '月')
            .fontSize(13)
            .fontColor($r('app.color.color_blue'))
            .backgroundColor($r('app.color.selected_day_bg'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .onClick(() => {
              this.calendarFormat = this.calendarFormat === 'month' ? 'week' : 'month';
            })

          Button('今')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.progress_bg'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .onClick(() => this.goToToday())

          Button({ type: ButtonType.Circle }) {
            Text('+').fontSize(18).fontColor($r('app.color.color_blue'))
          }
          .width(34).height(34)
          .backgroundColor($r('app.color.selected_day_bg'))
          .onClick(() => {
            const param: Record<string, ESObject> = { "isFixed": true };
            this.navStack.pushPathByName('TaskEdit', param);
          })
        }

        Button({ type: ButtonType.Circle }) {
          Text(this.viewMode === 'calendar' ? '📅' : '📋')
            .fontSize(16)
        }
        .width(34).height(34)
        .backgroundColor($r('app.color.progress_bg'))
        .onClick(() => {
          this.viewMode = this.viewMode === 'calendar' ? 'schedule' : 'calendar';
        })
      }
      .width('100%')
      .padding({ left: 20, right: 16, top: this.topRectHeight + 10, bottom: 12 })

      if (this.viewMode === 'schedule') {
        this.ScheduleGrid()
      } else {
        // 日历视图
        Column() {
          // 日历格子区域（可左右滑动切换月份/周）
          Stack() {
            Column({ space: 0 }) {
              this.WeekDayHeader()

              if (this.calendarFormat === 'month') {
                this.MonthGrid()
              } else {
                this.WeekRow()
              }
            }
          }
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionEnd((event: GestureEvent) => {
                if (event.offsetX > 60) {
                  if (this.calendarFormat === 'month') {
                    this.prevMonth();
                  } else {
                    this.prevWeek();
                  }
                } else if (event.offsetX < -60) {
                  if (this.calendarFormat === 'month') {
                    this.nextMonth();
                  } else {
                    this.nextWeek();
                  }
                }
              })
          )

          Divider().strokeWidth(0.5).color($r('app.color.separator')).margin({ top: 8, bottom: 4 })

          // 选中日期的事件列表（不受滑动手势影响）
          Scroll() {
            Column({ space: 0 }) {
              if (this.getDayPeriods(this.selectedDay).length === 0) {
                EmptyView({
                  icon: '📅',
                  title: '今日无事件',
                  subtitle: ''
                })
              } else {
                // 标题栏
                Row() {
                  Text('日程')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                  Text(`${this.getDayPeriods(this.selectedDay).length} 项`)
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 8 })

                ForEach(this.getDayPeriods(this.selectedDay), (p: Period, index: number) => {
                  this.EventCard(p)
                  if (index < this.getDayPeriods(this.selectedDay).length - 1) {
                    Divider()
                      .strokeWidth(0.5)
                      .color($r('app.color.progress_bg'))
                      .margin({ left: 56 })
                  }
                }, (p: Period) => p.uid)
              }
              Blank().height(64 + this.bottomRectHeight + 20)
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor($r('app.color.card_background'))
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .padding({ left: 16, right: 16, top: 8 })
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}

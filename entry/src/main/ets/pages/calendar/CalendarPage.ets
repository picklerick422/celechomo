// CalendarPage.ets - 日程页面（月/周日历视图）

import { Period, PeriodType, colorFromUid } from '../../model/Period';
import { Semester, PERIOD_TIMES } from '../../model/Semester';
import { CourseTimeSlot, Exam } from '../../model/Course';
import { AppKeys } from '../Index';
import { EmptyView } from '../../components/CommonComponents';

type CalendarFormat = 'month' | 'week';

interface MergedSlot {
  startPeriod: number;
  endPeriod: number;
  location: string;
}

interface CourseScheduleParam {
  semesterId: string;
  isFirstHalf: boolean;
}

const WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日'];
const MONTHS = ['1月', '2月', '3月', '4月', '5月', '6月',
  '7月', '8月', '9月', '10月', '11月', '12月'];

@Component
export struct CalendarPage {
  navStack: NavPathStack = new NavPathStack();
  @StorageLink(AppKeys.FLOW_LIST) flowList: Period[] = [];
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @State selectedDay: Date = new Date();
  @State focusedMonth: Date = new Date();
  @State calendarFormat: CalendarFormat = 'month';
  @State isRefreshing: boolean = false;
  @State swiperIndex: number = 2;
  @State swiperDuration: number = 250;
  @State isSwiperResetting: boolean = false;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;

  /** Swiper辅助:获取指定索引对应的月份(index 0~4,中心2=当月) */
  private getSwiperMonth(index: number): Date {
    const offset = index - 2;
    return new Date(this.focusedMonth.getFullYear(), this.focusedMonth.getMonth() + offset, 1);
  }

  /** Swiper辅助：获取指定索引对应的周一开始日期 */
  private getSwiperWeekMonday(index: number): Date {
    const currentMonday = this.getWeekMonday(this.selectedDay);
    const offset = (index - 2) * 7;
    const monday = new Date(currentMonday);
    monday.setDate(currentMonday.getDate() + offset);
    return monday;
  }

  /** 计算指定月份Grid所需高度 */
  private getMonthGridHeightForMonth(month: Date): number {
    const rowCount = this.getMonthCellsForMonth(month).length / 7;
    return rowCount * 50 + (rowCount - 1) * 2;
  }

  /** 获取指定日期所在周的周一 */
  private getWeekMonday(date: Date): Date {
    const day = date.getDay();
    const offset = day === 0 ? -6 : 1 - day;
    const monday = new Date(date);
    monday.setDate(date.getDate() + offset);
    return monday;
  }

  /** 判断两日期是否同月 */
  private isSameMonth(a: Date, b: Date): boolean {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth();
  }

  /** 获取指定月份的月历格子 */
  private getMonthCellsForMonth(month: Date): Date[] {
    const year = month.getFullYear();
    const m = month.getMonth();
    const firstDay = new Date(year, m, 1);
    const lastDay = new Date(year, m + 1, 0);
    let startOffset = firstDay.getDay() - 1;
    if (startOffset < 0) startOffset = 6;
    const cells: Date[] = [];
    for (let i = startOffset; i > 0; i--) {
      cells.push(new Date(year, m, 1 - i));
    }
    for (let d = 1; d <= lastDay.getDate(); d++) {
      cells.push(new Date(year, m, d));
    }
    while (cells.length % 7 !== 0) {
      cells.push(new Date(year, m + 1, cells.length - lastDay.getDate() - startOffset + 1));
    }
    return cells;
  }

  /** 获取指定月份的行模板（5行或6行） */
  private getMonthRowTemplateForMonth(month: Date): string {
    const rowCount = this.getMonthCellsForMonth(month).length / 7;
    return Array(rowCount).fill('1fr').join(' ');
  }

  /** 获取指定周周一的日期格子 */
  private getWeekCellsForWeek(monday: Date): Date[] {
    const cells: Date[] = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(monday);
      d.setDate(monday.getDate() + i);
      cells.push(d);
    }
    return cells;
  }

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
  private safeDate(d: Date | string | undefined | null): Date {
    if (d === undefined || d === null) {
      return new Date(0);
    }
    if (d instanceof Date) {
      return isNaN(d.getTime()) ? new Date(0) : d;
    }
    const parsed = new Date(d as string);
    return isNaN(parsed.getTime()) ? new Date(0) : parsed;
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

      // 判断当前日期属于哪个半学期（每半学期8周）
      const isDateInFirstHalf = weekDiff <= sem.halfSemesterWeeks;

      // 课程（需同时满足学期范围、有效周次、半学期匹配）
      if (inSemesterRange && validWeek) {
        for (const course of (sem.courses ?? [])) {
          // 收集该课程当天所有匹配的 timeSlots
          const matchedSlots: CourseTimeSlot[] = [];
          for (const slot of (course.timeSlots ?? [])) {
            // 半学期过滤：first=前半(秋/春), second=后半(冬/夏)
            if (slot.halfType === 'first' && !isDateInFirstHalf) continue;
            if (slot.halfType === 'second' && isDateInFirstHalf) continue;
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
      const examList: Exam[] = sem.exams ?? [];
      for (const exam of examList) {
        const examStart = this.safeDate(exam.startTime);
        const examEnd = this.safeDate(exam.endTime);
        if (this.isSameDay(examStart, date)) {
          periods.push(new Period(
            `exam_${exam.uid ?? 'unknown'}`,
            `${exam.courseName ?? '未知课程'} 考试`,
            examStart, examEnd,
            PeriodType.TEST, exam.location ?? '', exam.uid ?? ''
          ));
        }
      }
    }

    // 合并 flowList 中的用户自定义任务（排除已由 semesters 生成的课程/考试，避免重复）
    const flowEvents = this.flowList.filter(p => {
      if (p.type !== PeriodType.USER) return false;
      const d = this.safeDate(p.startTime);
      return d.getFullYear() === date.getFullYear() &&
        d.getMonth() === date.getMonth() &&
        d.getDate() === date.getDate();
    });
    periods.push(...flowEvents);

    return periods.sort((a, b) => {
      const at = isNaN(a.startTime.getTime()) ? 0 : a.startTime.getTime();
      const bt = isNaN(b.startTime.getTime()) ? 0 : b.startTime.getTime();
      return at - bt;
    });
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

  // ============= 课表跳转 =============

  private getCurrentSemester(): Semester | null {
    const now = new Date();
    for (const s of this.semesters) {
      const sStart = this.safeDate(s.startDate);
      const sEnd = this.safeDate(s.endDate);
      if (sStart <= now && now <= sEnd) return s;
    }
    return this.semesters.length > 0 ? this.semesters[this.semesters.length - 1] : null;
  }

  private buildCourseScheduleParam(): CourseScheduleParam | null {
    const sem = this.getCurrentSemester();
    if (!sem) return null;
    const week = typeof sem.currentWeek === 'function' ? sem.currentWeek(new Date()) : 0;
    const isFirstHalf = week > 0 ? week <= (sem.halfSemesterWeeks ?? 8) : true;
    return { semesterId: sem.id, isFirstHalf };
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

  /** 计算月视图需要多少行（5行或6行） */
  private getMonthRowTemplate(): string {
    const rowCount = this.getMonthCells().length / 7;
    return Array(rowCount).fill('1fr').join(' ');
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
    .rowsTemplate(this.getMonthRowTemplate())
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
    this.DayCellForMonth(date, this.focusedMonth, true)
  }

  @Builder
  DayCellForMonth(date: Date, targetMonth: Date, grayOutOfMonth: boolean) {
    Column({ space: 2 }) {
      Text(date.getDate().toString())
        .fontSize(15)
        .fontColor(
          this.isSameDay(date, this.selectedDay) ? Color.White :
            (grayOutOfMonth && !this.isSameMonth(date, targetMonth)) ? $r('app.color.text_tertiary') :
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
      if (!this.isSameMonth(date, this.focusedMonth)) {
        this.focusedMonth = new Date(date.getFullYear(), date.getMonth(), 1);
      }
    })
  }

  @Builder
  MonthGridForMonth(month: Date) {
    Grid() {
      ForEach(this.getMonthCellsForMonth(month), (date: Date) => {
        GridItem() {
          this.DayCellForMonth(date, month, true)
        }
      }, (date: Date) => `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`)
    }
    .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
    .rowsTemplate(this.getMonthRowTemplateForMonth(month))
    .columnsGap(0)
    .rowsGap(2)
    .padding({ left: 8, right: 8 })
    .height(this.getMonthGridHeightForMonth(month))
  }

  @Builder
  WeekRowForWeek(monday: Date) {
    Row() {
      ForEach(this.getWeekCellsForWeek(monday), (date: Date) => {
        this.DayCellForMonth(date, monday, false)
      }, (date: Date) => `week-${date.getDate()}`)
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
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

  build() {
    Column() {
      // 标题栏
      Row() {
        Column({ space: 4 }) {
          Text(`${this.focusedMonth.getFullYear()}年${MONTHS[this.focusedMonth.getMonth()]}`)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.isToday(this.selectedDay) ? '今天' :
            `${this.selectedDay.getMonth() + 1}月${this.selectedDay.getDate()}日`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        // 右上角按钮组 - 统一风格
        Row({ space: 8 }) {
          // 周/月切换
          Text(this.calendarFormat === 'month' ? '周' : '月')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_blue'))
            .backgroundColor($r('app.color.selected_day_bg'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(16)
            .onClick(() => {
              this.calendarFormat = this.calendarFormat === 'month' ? 'week' : 'month';
            })

          // 跳到今天
          Text('今')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_blue'))
            .backgroundColor($r('app.color.selected_day_bg'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(16)
            .onClick(() => this.goToToday())

          // 新建任务
          Button({ type: ButtonType.Circle }) {
            Image($r('sys.media.ohos_ic_public_add'))
              .width(16).height(16)
              .fillColor($r('app.color.color_blue'))
          }
          .width(32).height(32)
          .backgroundColor($r('app.color.selected_day_bg'))
          .onClick(() => {
            const param: Record<string, ESObject> = { "isFixed": true };
            this.navStack.pushPathByName('TaskEdit', param);
          })

          // 跳到课表
          Text('课表')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.progress_bg'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(16)
            .onClick(() => {
              const param = this.buildCourseScheduleParam();
              if (param) this.navStack.pushPathByName('CourseSchedule', param);
            })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 16, top: this.topRectHeight + 10, bottom: 12 })

      // 日历视图
      Column({ space: 0 }) {
        this.WeekDayHeader()

          // 日历格子区域（Swiper左右滑动切换月份/周）
          Swiper() {
            // 上上月
            Column({ space: 0 }) {
              if (this.calendarFormat === 'month') {
                this.MonthGridForMonth(this.getSwiperMonth(0))
              } else {
                this.WeekRowForWeek(this.getSwiperWeekMonday(0))
              }
            }
            .width('100%')

            // 上月
            Column({ space: 0 }) {
              if (this.calendarFormat === 'month') {
                this.MonthGridForMonth(this.getSwiperMonth(1))
              } else {
                this.WeekRowForWeek(this.getSwiperWeekMonday(1))
              }
            }
            .width('100%')

            // 当前月
            Column({ space: 0 }) {
              if (this.calendarFormat === 'month') {
                this.MonthGridForMonth(this.getSwiperMonth(2))
              } else {
                this.WeekRowForWeek(this.getSwiperWeekMonday(2))
              }
            }
            .width('100%')

            // 下月
            Column({ space: 0 }) {
              if (this.calendarFormat === 'month') {
                this.MonthGridForMonth(this.getSwiperMonth(3))
              } else {
                this.WeekRowForWeek(this.getSwiperWeekMonday(3))
              }
            }
            .width('100%')

            // 下下月
            Column({ space: 0 }) {
              if (this.calendarFormat === 'month') {
                this.MonthGridForMonth(this.getSwiperMonth(4))
              } else {
                this.WeekRowForWeek(this.getSwiperWeekMonday(4))
              }
            }
            .width('100%')
          }
          .index(this.swiperIndex)
          .duration(this.swiperDuration)
          .loop(false)
          .indicator(false)
          .onAnimationEnd((index: number) => {
            if (this.isSwiperResetting || index === 2) return;
            this.isSwiperResetting = true;
            const offset = index - 2;
            if (this.calendarFormat === 'month') {
              this.focusedMonth = new Date(this.focusedMonth.getFullYear(), this.focusedMonth.getMonth() + offset, 1);
            } else {
              this.selectedDay = new Date(this.selectedDay.getTime() + offset * 7 * 86400000);
            }
            setTimeout(() => {
              this.swiperIndex = 2;
              this.isSwiperResetting = false;
            }, 50);
          })

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
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}

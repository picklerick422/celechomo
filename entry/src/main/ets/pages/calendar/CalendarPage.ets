// CalendarPage.ets - 日程页面（日历视图 + 课表视图）

import { Period, PeriodType, colorFromUid } from '../../model/Period';
import { Semester, PERIOD_TIMES } from '../../model/Semester';
import { AppKeys } from '../Index';
import { ColorIndicator, EmptyView } from '../../components/CommonComponents';

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

interface ScheduleCourseItemWithTeacher {
  name: string;
  location: string;
  weekDay: number;
  startPeriod: number;
  endPeriod: number;
  color: string;
  teacher: string;
}

interface CustomGpaResult {
  gpa: number;
  credits: number;
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

    // 周一起始，firstDay.getDay(): 0=日 1=一 ... 6=六
    let startOffset = firstDay.getDay() - 1;
    if (startOffset < 0) startOffset = 6; // 周日

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

  /** 某天是否有事件 */
  private hasEvents(date: Date): boolean {
    return this.getEventsForDay(date).length > 0;
  }

  /** 获取某天的事件列表 */
  private getEventsForDay(date: Date): Period[] {
    return this.flowList.filter(p => {
      const d = p.startTime;
      return d.getFullYear() === date.getFullYear() &&
        d.getMonth() === date.getMonth() &&
        d.getDate() === date.getDate();
    });
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

  // ============= 课表视图 =============

  private getCurrentSemester(): Semester | null {
    const now = new Date();
    for (const s of this.semesters) {
      if (s.startDate <= now && now <= s.endDate) return s;
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
      // 月份导航
      if (this.calendarFormat === 'month') {
        Button({ type: ButtonType.Circle }) {
          Image($r('sys.media.ohos_ic_public_arrow_left'))
            .width(16).height(16)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(32).height(32)
        .backgroundColor(Color.Transparent)
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
        .backgroundColor(Color.Transparent)
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
          .padding({ bottom: 8 })
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
    Column({ space: 3 }) {
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
        .fontWeight(this.isToday(date) || this.isSameDay(date, this.selectedDay) ? 600 : FontWeight.Regular) // SemiBold : Regular
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

      // 事件指示点
      Row()
        .width(5)
        .height(5)
        .borderRadius(2.5)
        .backgroundColor(this.hasEvents(date) ?
          (this.isSameDay(date, this.selectedDay) ? Color.White : $r('app.color.color_blue')) :
          Color.Transparent
        )
    }
    .width('14.28%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 6, bottom: 6 })
    .onClick(() => {
      this.selectedDay = date;
      if (!this.isCurrentMonth(date)) {
        this.focusedMonth = date;
      }
    })
  }

  @Builder
  EventCard(period: Period) {
    Row({ space: 14 }) {
      // 左侧色条
      Column()
        .width(4)
        .height('100%')
        .borderRadius(2)
        .backgroundColor(this.getPeriodColor(period))

      Column({ space: 6 }) {
        Text(period.summary)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 10 }) {
          Text(this.formatEventTime(period))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          if (period.location.length > 0) {
            Text(period.location)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .shadow({
      radius: 8,
      color: '#10000000',
      offsetX: 0,
      offsetY: 3
    })
  }

  @Builder
  ScheduleGrid() {
    Column() {
      // 切换前/后半学期
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

      // 表头（星期列）
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
        // 课表网格 - 使用 Stack 实现绝对定位
        Stack({ alignContent: Alignment.TopStart }) {
          // 背景格子线
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

          // 课程卡片
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
      // 标题栏 - 现代化设计
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
          // 格式切换
          Button(this.calendarFormat === 'month' ? '周视图' : '月视图')
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.color_blue'))
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(16)
            .shadow({
              radius: 6,
              color: '#30007AFF',
              offsetX: 0,
              offsetY: 3
            })
            .onClick(() => {
              this.calendarFormat = this.calendarFormat === 'month' ? 'week' : 'month';
            })

          // 今天按钮
          Button('今天')
            .fontSize(13)
            .backgroundColor($r('app.color.progress_bg'))
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(16)
            .onClick(() => this.goToToday())

          // 添加日程
          Button({ type: ButtonType.Circle }) {
            Text('+').fontSize(20).fontColor(Color.White)
          }
          .width(36).height(36)
          .backgroundColor($r('app.color.color_blue'))
          .shadow({
            radius: 8,
            color: '#30007AFF',
            offsetX: 0,
            offsetY: 4
          })
          .onClick(() => {
            const param: Record<string, ESObject> = { "isFixed": true };
            this.navStack.pushPathByName('TaskEdit', param);
          })
        }

        // 视图切换
        Button({ type: ButtonType.Circle }) {
          Text(this.viewMode === 'calendar' ? '📅' : '📋')
            .fontSize(16)
        }
        .width(36).height(36)
        .backgroundColor($r('app.color.progress_bg'))
        .onClick(() => {
          this.viewMode = this.viewMode === 'calendar' ? 'schedule' : 'calendar';
        })
      }
      .width('100%')
      .padding({ left: 20, right: 16, top: this.topRectHeight + 10, bottom: 12 })

      if (this.viewMode === 'schedule') {
        // 课表视图
        this.ScheduleGrid()
      } else {
        // 日历视图
        Column() {
          this.WeekDayHeader()

          if (this.calendarFormat === 'month') {
            this.MonthGrid()
          } else {
            this.WeekRow()
          }

          Divider().strokeWidth(0.5).color($r('app.color.separator')).margin({ top: 8, bottom: 4 })

          // 选中日期的事件列表
          Scroll() {
            Column({ space: 8 }) {
              if (this.getEventsForDay(this.selectedDay).length === 0) {
                EmptyView({
                  icon: '📅',
                  title: '今日无事件',
                  subtitle: ''
                })
              } else {
                ForEach(this.getEventsForDay(this.selectedDay), (p: Period) => {
                  this.EventCard(p)
                }, (p: Period) => p.uid)
              }
              Blank().height(64 + this.bottomRectHeight + 20)
            }
            .padding({ left: 16, right: 16, top: 8 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}

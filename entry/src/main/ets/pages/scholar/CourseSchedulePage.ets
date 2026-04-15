// CourseSchedulePage.ets - 课表页面

import { Semester, PERIOD_TIMES } from '../../model/Semester';
import { Course } from '../../model/Course';
import { colorFromUid } from '../../model/Period';
import { AppKeys } from '../Index';

const WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日'];
const ROW_HEIGHT_COURSE = 52;
const LABEL_PCT_COURSE = 10.5;
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
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @State semesterId: string = '';
  @State isFirstHalf: boolean = true;
  private pathStack: NavPathStack | null = null;

  private get currentSemester(): Semester | null {
    return this.semesters.find(s => s.id === this.semesterId) ?? null;
  }

  private getScheduleCourses(): ScheduleCourseItemWithTeacher[] {
    const sem = this.currentSemester;
    if (!sem) return [];
    const result: ScheduleCourseItemWithTeacher[] = [];
    for (const course of sem.courses) {
      const color = colorFromUid(course.uid);
      for (const slot of course.timeSlots) {
        if (slot.isFirstHalf !== this.isFirstHalf) continue;
        const item: ScheduleCourseItemWithTeacher = {
          name: course.shortName || course.name.slice(0, 6),
          location: slot.location,
          weekDay: slot.weekDay,
          startPeriod: slot.startPeriod,
          endPeriod: slot.endPeriod,
          color,
          teacher: course.teacher
        };
        result.push(item);
      }
    }
    return result;
  }

  private formatPeriodTime(idx: number): string {
    const time = PERIOD_TIMES[idx];
    if (!time) return '';
    const h = Math.floor(time[0] / 60);
    const m = time[0] % 60;
    return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}`;
  }

  build() {
    NavDestination() {
      Column() {
        // 导航栏
        Row() {
          Button({ type: ButtonType.Normal }) {
            Image($r('sys.media.ohos_ic_public_arrow_left'))
              .width(22).height(22).fillColor($r('app.color.color_blue'))
          }
          .backgroundColor(Color.Transparent).padding(8)
          .onClick(() => this.pathStack?.pop())

          Text('课表').fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)

          Row().width(46)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        // 前/后半切换
        Row({ space: 8 }) {
          Text('前半学期')
            .fontSize(14)
            .fontColor(this.isFirstHalf ? $r('app.color.color_blue') : $r('app.color.text_secondary'))
            .fontWeight(this.isFirstHalf ? FontWeight.Medium : FontWeight.Regular)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(20)
            .backgroundColor(this.isFirstHalf ? $r('app.color.selected_day_bg') : Color.Transparent)
            .onClick(() => { this.isFirstHalf = true; })

          Text('后半学期')
            .fontSize(14)
            .fontColor(!this.isFirstHalf ? $r('app.color.color_blue') : $r('app.color.text_secondary'))
            .fontWeight(!this.isFirstHalf ? FontWeight.Medium : FontWeight.Regular)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(20)
            .backgroundColor(!this.isFirstHalf ? $r('app.color.selected_day_bg') : Color.Transparent)
            .onClick(() => { this.isFirstHalf = false; })
        }
        .padding({ left: 16, top: 8, bottom: 4 })
        .width('100%')

        // 表头
        Row() {
          Text('').width(40)
          ForEach(WEEKDAYS, (day: string) => {
            Text(day)
              .fontSize(12).fontColor($r('app.color.text_secondary'))
              .layoutWeight(1).textAlign(TextAlign.Center)
          })
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 4 })

        Scroll() {
          Stack({ alignContent: Alignment.TopStart }) {
            // 背景格子
            Column() {
              ForEach(PERIOD_LABELS_COURSE, (label: string, idx: number) => {
                Row() {
                  Column() {
                    Text(label)
                      .fontSize(10).fontColor($r('app.color.text_tertiary')).textAlign(TextAlign.Center)
                    Text(this.formatPeriodTime(idx))
                      .fontSize(9).fontColor($r('app.color.text_tertiary')).textAlign(TextAlign.Center)
                  }
                  .width(40).height(ROW_HEIGHT_COURSE).justifyContent(FlexAlign.Center)

                  ForEach(WEEKDAYS, (_: string) => {
                    Row()
                      .layoutWeight(1).height(ROW_HEIGHT_COURSE)
                      .border({
                        width: { left: 0.5, bottom: 0.5 },
                        color: $r('app.color.separator'),
                        style: BorderStyle.Dashed
                      })
                  })
                }
                .width('100%')
              })
            }
            .width('100%')

            // 课程卡片绝对定位
            ForEach(this.getScheduleCourses(), (course: ScheduleCourseItemWithTeacher) => {
              this.CourseBlock(course)
            }, (c: ScheduleCourseItemWithTeacher) => `${c.weekDay}-${c.startPeriod}`)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%').height('100%').backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as Record<string, string | boolean>;
      this.semesterId = (params?.['semesterId'] as string) ?? '';
      this.isFirstHalf = params?.['isFirstHalf'] !== false;
    })
  }

  @Builder
  CourseBlock(course: ScheduleCourseItemWithTeacher) {
    Column({ space: 2 }) {
      Text(course.name)
        .fontSize(10).fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      if (course.location.length > 0) {
        Text(course.location)
          .fontSize(9).fontColor(Color.White).opacity(0.85)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
    }
    .width(`${COL_WIDTH_PCT_COURSE}%`)
    .height((course.endPeriod - course.startPeriod + 1) * ROW_HEIGHT_COURSE - 3)
    .borderRadius(6)
    .backgroundColor(course.color)
    .padding(4)
    .clip(true)
    .position({ x: `${LABEL_PCT_COURSE + (course.weekDay - 1) * COL_WIDTH_PCT_COURSE}%`, y: (course.startPeriod - 1) * ROW_HEIGHT_COURSE })
  }
}

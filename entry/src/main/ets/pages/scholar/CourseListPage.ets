// CourseListPage.ets - 课程列表页

import { Semester } from '../../model/Semester';
import { Course } from '../../model/Course';
import { AppKeys } from '../Index';

@Component
export struct CourseListPage {
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @State semesterId: string = '';
  private pathStack: NavPathStack | null = null;

  private get currentSemester(): Semester | null {
    return this.semesters.find(s => s.id === this.semesterId) ?? null;
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Button({ type: ButtonType.Normal }) {
            Image($r('sys.media.ohos_ic_public_arrow_left'))
              .width(22).height(22).fillColor($r('app.color.color_blue'))
          }
          .backgroundColor(Color.Transparent).padding(8)
          .onClick(() => this.pathStack?.pop())

          Text('课程').fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)

          Row().width(46)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        if (this.currentSemester !== null) {
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.currentSemester.courses, (course: Course) => {
                Row({ space: 12 }) {
                  Row()
                    .width(4).height('100%')
                    .borderRadius(2)
                    .backgroundColor(course.color)

                  Column({ space: 4 }) {
                    Text(course.name)
                      .fontSize(16).fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row({ space: 8 }) {
                      Text(course.teacher).fontSize(13).fontColor($r('app.color.text_secondary'))
                      Text(`${course.credits} 学分`).fontSize(13).fontColor($r('app.color.text_tertiary'))
                    }
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)

                  if (course.hasGrade) {
                    Text(course.grade.toString())
                      .fontSize(18).fontWeight(FontWeight.Medium)
                      .fontColor(course.grade >= 60 ? $r('app.color.text_primary') : $r('app.color.color_red'))
                  }
                }
                .width('100%').padding(16)
                .backgroundColor($r('app.color.card_background')).borderRadius(12)
              }, (c: Course) => c.uid)

              Blank().height(80)
            }
            .padding(16)
          }
          .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as Record<string, string>;
      this.semesterId = params?.['semesterId'] ?? '';
    })
  }
}


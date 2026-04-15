// ExamListPage.ets - 独立导出（避免循环引用）

import { Semester } from '../../model/Semester';
import { Exam } from '../../model/Course';
import { AppKeys } from '../Index';

@Component
export struct ExamListPage {
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @State semesterId: string = '';
  private pathStack: NavPathStack | null = null;

  private get currentSemester(): Semester | null {
    return this.semesters.find(s => s.id === this.semesterId) ?? null;
  }

  private formatExamTime(exam: Exam): string {
    const d = exam.startTime;
    const end = exam.endTime;
    return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')} - ${end.getHours().toString().padStart(2, '0')}:${end.getMinutes().toString().padStart(2, '0')}`;
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

          Text('考试').fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)

          Row().width(46)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        // 警告横幅
        Row({ space: 8 }) {
          Text('⚠️').fontSize(14)
          Text('请务必前往教务网核对考试信息').fontSize(13).fontColor($r('app.color.color_red'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor('#FFEBEE')

        if (this.currentSemester !== null) {
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.currentSemester.exams, (exam: Exam) => {
                Column({ space: 10 }) {
                  Row({ space: 10 }) {
                    Row()
                      .width(12).height(12)
                      .borderRadius(exam.type === 'midterm' ? 6 : 2)
                      .backgroundColor('#F48FB1')

                    Text(exam.courseName)
                      .fontSize(16).fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)

                    Text(exam.type === 'midterm' ? '期中' : '期末')
                      .fontSize(12).fontColor($r('app.color.text_secondary'))
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(10).backgroundColor($r('app.color.progress_bg'))
                  }

                  Text(this.formatExamTime(exam))
                    .fontSize(14).fontColor($r('app.color.text_secondary'))

                  Row({ space: 20 }) {
                    if (exam.location.length > 0) {
                      Row({ space: 4 }) {
                        Image($r('sys.media.ohos_ic_public_location'))
                          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
                        Text(exam.location).fontSize(13).fontColor($r('app.color.text_tertiary'))
                      }
                    }
                    if (exam.seatNo.length > 0) {
                      Text(`座位号: ${exam.seatNo}`)
                        .fontSize(13).fontColor($r('app.color.text_tertiary'))
                    }
                  }
                }
                .width('100%').padding(16)
                .backgroundColor($r('app.color.card_background')).borderRadius(12)
                .alignItems(HorizontalAlign.Start)
              }, (e: Exam) => e.uid)

              Blank().height(80)
            }
            .padding(16)
          }
          .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).layoutWeight(1)
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

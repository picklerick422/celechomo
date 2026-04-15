// GradeDetailPage.ets - 成绩详情页

import { Semester } from '../../model/Semester';
import { Course } from '../../model/Course';
import { AppKeys } from '../Index';
import { TwoLineCard } from '../../components/CommonComponents';

interface CustomGpaResult {
  gpa: number;
  credits: number;
}

@Component
export struct GradeDetailPage {
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @StorageLink(AppKeys.HIDE_GPA) hideGpa: boolean = false;
  @State semesterIndex: number = 0;
  @State customMode: boolean = false;
  @State selectedCourses: Set<string> = new Set();
  private pathStack: NavPathStack | null = null;

  private get currentSemester(): Semester | null {
    return this.semesters[this.semesterIndex] ?? null;
  }

  private fmt(val: number): string {
    if (this.hideGpa) return '***';
    return val > 0 ? val.toFixed(2) : '-';
  }

  private computeCustomGpa(): CustomGpaResult {
    const sem = this.currentSemester;
    if (!sem || this.selectedCourses.size === 0) {
      const result: CustomGpaResult = { gpa: 0, credits: 0 };
      return result;
    }
    const selected = sem.courses.filter(c => this.selectedCourses.has(c.uid) && c.hasGrade);
    const totalCredits = selected.reduce((s, c) => s + c.credits, 0);
    if (totalCredits === 0) {
      const result: CustomGpaResult = { gpa: 0, credits: 0 };
      return result;
    }
    const weightedGpa = selected.reduce((s, c) => s + (c.gradePoint > 0 ? c.gradePoint : 0) * c.credits, 0);
    const result: CustomGpaResult = { gpa: weightedGpa / totalCredits, credits: totalCredits };
    return result;
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
          .backgroundColor(Color.Transparent)
          .padding(8)
          .onClick(() => this.pathStack?.pop())

          Text('成绩')
            .fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)

          Button(this.customMode ? '取消自定义' : '自定义GPA')
            .fontSize(13)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.color_blue'))
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              this.customMode = !this.customMode;
              if (!this.customMode) this.selectedCourses = new Set();
            })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        Scroll() {
          Column({ space: 16 }) {
            // 成绩概览 6 卡片
            if (this.currentSemester !== null) {
              Grid() {
                GridItem() { TwoLineCard({ title: '学年学分', value: this.currentSemester.gpaInfo.yearCredits.toFixed(1) }).padding(12) }
                GridItem() { TwoLineCard({ title: '学年均绩', value: this.fmt(this.currentSemester.gpaInfo.yearGpa) }).padding(12) }
                GridItem() { TwoLineCard({ title: '四分制GPA', value: this.fmt(this.currentSemester.gpaInfo.rawFourPointGpa) }).padding(12) }
                GridItem() { TwoLineCard({ title: '主修学分', value: this.currentSemester.gpaInfo.majorCredits.toFixed(1) }).padding(12) }
                GridItem() { TwoLineCard({ title: '主修均绩', value: this.fmt(this.currentSemester.gpaInfo.majorGpa) }).padding(12) }
                GridItem() { TwoLineCard({ title: '主修四分制', value: this.fmt(this.currentSemester.gpaInfo.majorFourGpa) }).padding(12) }
              }
              .columnsTemplate('1fr 1fr 1fr')
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(16)

              // 自定义 GPA 结果
              if (this.customMode) {
                Row({ space: 16 }) {
                  Column({ space: 4 }) {
                    Text('自定义GPA').fontSize(12).fontColor($r('app.color.text_secondary'))
                    Text(this.computeCustomGpa().gpa > 0 ? this.computeCustomGpa().gpa.toFixed(3) : '-')
                      .fontSize(22).fontWeight(FontWeight.Medium).fontColor($r('app.color.color_blue'))
                  }
                  Column({ space: 4 }) {
                    Text('已选学分').fontSize(12).fontColor($r('app.color.text_secondary'))
                    Text(this.computeCustomGpa().credits.toFixed(1))
                      .fontSize(22).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  }
                  Blank()
                  Button('长按清空')
                    .fontSize(12)
                    .backgroundColor($r('app.color.color_red') + '20')
                    .fontColor($r('app.color.color_red'))
                    .borderRadius(10)
                    .gesture(LongPressGesture().onAction(() => {
                      this.selectedCourses = new Set();
                    }))
                }
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(16)
              }

              // 学期选择器
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.semesters, (s: Semester, idx: number) => {
                    Column({ space: 4 }) {
                      Text(s.name)
                        .fontSize(13)
                        .fontColor(idx === this.semesterIndex ? Color.White : $r('app.color.text_secondary'))
                      Text(this.fmt(s.gpaInfo.fivePointGpa))
                        .fontSize(12)
                        .fontColor(idx === this.semesterIndex ? Color.White : $r('app.color.text_tertiary'))
                    }
                    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                    .borderRadius(14)
                    .backgroundColor(idx === this.semesterIndex ?
                      $r('app.color.color_blue') : $r('app.color.progress_bg'))
                    .onClick(() => { this.semesterIndex = idx; })
                  })
                }
                .padding({ left: 0, right: 0 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)

              // 课程成绩列表
              Column({ space: 8 }) {
                ForEach(this.currentSemester.courses.filter(c => c.hasGrade), (course: Course) => {
                  Row({ space: 12 }) {
                    if (this.customMode) {
                      Toggle({ type: ToggleType.Checkbox, isOn: this.selectedCourses.has(course.uid) })
                        .onChange((isOn: boolean) => {
                          const newSet = new Set(this.selectedCourses);
                          if (isOn) newSet.add(course.uid);
                          else newSet.delete(course.uid);
                          this.selectedCourses = newSet;
                        })
                    }
                    Column({ space: 4 }) {
                      Text(course.name)
                        .fontSize(15).fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`${course.credits} 学分`)
                        .fontSize(12).fontColor($r('app.color.text_secondary'))
                    }
                    .layoutWeight(1).alignItems(HorizontalAlign.Start)

                    Column({ space: 4 }) {
                      Text(course.grade > 0 ? course.grade.toString() : '-')
                        .fontSize(18).fontWeight(FontWeight.Medium)
                        .fontColor(course.grade >= 60 ? $r('app.color.text_primary') : $r('app.color.color_red'))
                      Text(course.gradeLevel.length > 0 ? course.gradeLevel : (course.gradePoint > 0 ? course.gradePoint.toFixed(1) : ''))
                        .fontSize(12).fontColor($r('app.color.text_tertiary'))
                    }
                    .alignItems(HorizontalAlign.End)
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                  .backgroundColor($r('app.color.card_background'))
                  .borderRadius(12)
                }, (c: Course) => c.uid)
              }
            }

            Blank().height(80)
          }
          .padding(16)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as Record<string, number>;
      this.semesterIndex = params?.['semesterIndex'] ?? this.semesters.length - 1;
    })
  }
}

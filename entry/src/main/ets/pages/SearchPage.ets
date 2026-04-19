// SearchPage.ets - 全局课程搜索页

import { Semester } from '../model/Semester';
import { Course } from '../model/Course';
import { colorFromUid } from '../model/Period';
import { AppKeys } from './Index';


@Component
export struct SearchPage {
  @StorageLink(AppKeys.SEMESTERS) @Watch('onSemestersChanged') semesters: Semester[] = [];
  @State searchWord: string = '';
  @State results: Course[] = [];
  private allCourses: Course[] = [];
  private pathStack: NavPathStack | null = null;

  aboutToAppear(): void {
    this.rebuildAllCourses();
  }

  private onSemestersChanged(): void {
    this.rebuildAllCourses();
    // 如果当前有搜索词，重新执行搜索
    if (this.searchWord.length > 0) {
      this.search(this.searchWord);
    }
  }

  private rebuildAllCourses(): void {
    this.allCourses = [];
    for (const sem of this.semesters) {
      for (const course of sem.courses) {
        if (!this.allCourses.some(c => c.courseId === course.courseId)) {
          this.allCourses.push(course);
        }
      }
    }
    console.info(`[SearchPage] Rebuilt allCourses: ${this.allCourses.length} unique courses`);
  }

  private search(keyword: string): void {
    this.searchWord = keyword;
    if (keyword.trim().length === 0) {
      this.results = [];
      return;
    }
    const kw = keyword.toLowerCase();
    this.results = this.allCourses.filter(c =>
      c.name.toLowerCase().includes(kw) ||
      c.courseId.toLowerCase().includes(kw) ||
      c.teacher.toLowerCase().includes(kw)
    );
  }

  build() {
    NavDestination() {
      Column() {
        // 搜索栏
        Row({ space: 12 }) {
          Row({ space: 8 }) {
            Text('🔍')
              .fontSize(16)
            TextInput({ text: this.searchWord, placeholder: '搜索课程、事项...' })
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_tertiary'))
              .backgroundColor(Color.Transparent)
              .border({ width: 0 })
              .layoutWeight(1)
              .defaultFocus(true)
              .onChange((text: string) => this.search(text))
          }
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(12)
          .backgroundColor($r('app.color.progress_bg'))

          Button('取消')
            .fontSize(15)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.color_blue'))
            .padding({ left: 8, right: 8 })
            .onClick(() => this.pathStack?.pop())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        if (this.results.length === 0 && this.searchWord.length === 0) {
          Column({ space: 12 }) {
            Text('🔍').fontSize(48).padding({ top: 60 })
            Text('搜索课程').fontSize(17).fontColor($r('app.color.text_secondary'))
            Text('输入课程名称、课程代码或教师姓名')
              .fontSize(14).fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        } else if (this.results.length === 0 && this.searchWord.length > 0) {
          Column({ space: 12 }) {
            Text('😕').fontSize(48).padding({ top: 60 })
            Text('无搜索结果').fontSize(17).fontColor($r('app.color.text_secondary'))
            Text(`没有找到与"${this.searchWord}"相关的课程`)
              .fontSize(14).fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center).padding({ left: 32, right: 32 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column({ space: 8 }) {
              Text(`${this.results.length} 个结果`)
                .fontSize(13).fontColor($r('app.color.text_tertiary'))
                .padding({ left: 4 })

              ForEach(this.results, (course: Course) => {
                Row({ space: 12 }) {
                  Row()
                    .width(4).height('100%')
                    .borderRadius(2)
                    .backgroundColor(colorFromUid(course.uid))

                  Column({ space: 4 }) {
                    Text(course.name)
                      .fontSize(16).fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row({ space: 8 }) {
                      Text(course.courseId).fontSize(12).fontColor($r('app.color.text_tertiary'))
                      if (course.teacher.length > 0) {
                        Text(course.teacher).fontSize(12).fontColor($r('app.color.text_secondary'))
                      }
                      Text(`${course.credits} 学分`).fontSize(12).fontColor($r('app.color.text_tertiary'))
                    }
                    if (course.semester.length > 0) {
                      Text(course.semester).fontSize(11).fontColor($r('app.color.text_tertiary'))
                    }
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)

                  if (course.hasGrade) {
                    Column({ space: 2 }) {
                      Text(course.grade.toString())
                        .fontSize(20).fontWeight(FontWeight.Medium)
                        .fontColor(course.grade >= 60 ? $r('app.color.text_primary') : $r('app.color.color_red'))
                      Text(course.gradeLevel)
                        .fontSize(11).fontColor($r('app.color.text_tertiary'))
                    }
                    .alignItems(HorizontalAlign.End)
                  }
                }
                .width('100%').padding(16)
                .backgroundColor($r('app.color.card_background')).borderRadius(12)
              }, (c: Course) => c.uid)

              Blank().height(80)
            }
            .padding(16)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => { this.pathStack = ctx.pathStack; })
  }
}

// SearchPage.ets - 全局课程搜索页（美化版）

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
    if (this.searchWord.length > 0) {
      this.search(this.searchWord);
    }
  }

  private rebuildAllCourses(): void {
    this.allCourses = [];
    for (const sem of this.semesters) {
      for (const course of sem.courses) {
        const key = course.courseId.length > 0 ? course.courseId : course.uid;
        if (!this.allCourses.some(c => {
          const otherKey = c.courseId.length > 0 ? c.courseId : c.uid;
          return otherKey === key;
        })) {
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

  private getGradeColor(grade: number): string {
    if (grade >= 90) return '#4CAF50';
    if (grade >= 80) return '#2196F3';
    if (grade >= 60) return '#FF9800';
    return '#F44336';
  }

  private getGradeLabel(grade: number): string {
    if (grade >= 90) return '优秀';
    if (grade >= 80) return '良好';
    if (grade >= 70) return '中等';
    if (grade >= 60) return '及格';
    return '不及格';
  }

  build() {
    NavDestination() {
      Column() {
        // ── 搜索栏 ──
        Row({ space: 12 }) {
          Row({ space: 8 }) {
            Text('🔍')
              .fontSize(18)
              .fontColor($r('app.color.text_tertiary'))
            TextInput({ text: this.searchWord, placeholder: '搜索课程、教师...' })
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
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .borderRadius(14)
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

        // ── 初始状态 ──
        if (this.results.length === 0 && this.searchWord.length === 0) {
          Column({ space: 16 }) {
            Column() {
              Text('🔍')
                .fontSize(56)
            }
            .width(100)
            .height(100)
            .borderRadius(50)
            .backgroundColor($r('app.color.progress_bg'))
            .justifyContent(FlexAlign.Center)
            .margin({ top: 80 })

            Text('搜索课程')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))

            Text('输入课程名称、课程代码或教师姓名')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .padding({ left: 40, right: 40 })

            if (this.allCourses.length > 0) {
              Text(`共 ${this.allCourses.length} 门课程可搜索`)
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 8 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)

        // ── 无结果状态 ──
        } else if (this.results.length === 0 && this.searchWord.length > 0) {
          Column({ space: 16 }) {
            Column() {
              Text('😕')
                .fontSize(56)
            }
            .width(100)
            .height(100)
            .borderRadius(50)
            .backgroundColor($r('app.color.progress_bg'))
            .justifyContent(FlexAlign.Center)
            .margin({ top: 80 })

            Text('无搜索结果')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))

            Text(`没有找到与 "${this.searchWord}" 相关的课程`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .padding({ left: 40, right: 40 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)

        // ── 搜索结果列表 ──
        } else {
          Scroll() {
            Column({ space: 10 }) {
              // 结果统计
              Row() {
                Text(`找到 ${this.results.length} 个结果`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_tertiary'))
                Blank()
                Text(`${this.allCourses.length} 门课程总计`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')
              .padding({ left: 4, right: 4 })

              ForEach(this.results, (course: Course) => {
                this.SearchResultCard(course)
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

  @Builder
  SearchResultCard(course: Course) {
    Row({ space: 10 }) {
      // 左侧颜色条
      Row()
        .width(3)
        .height(44)
        .borderRadius(2)
        .backgroundColor(colorFromUid(course.uid))

      // 中间内容区
      Column({ space: 3 }) {
        // 课程名
        Text(course.name.length > 0 ? course.name : '未命名课程')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 教师 + 学分
        Row({ space: 6 }) {
          if (course.teacher.length > 0) {
            Text(course.teacher)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (course.credits > 0) {
            Text(`${course.credits.toFixed(1)} 学分`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          } else if (!course.hasGrade) {
            Text('未完结')
              .fontSize(10)
              .fontColor('#FF9800')
          }
        }

        // 学期标签
        if (course.semester.length > 0 && course.semester !== '-') {
          Text(course.semester)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧状态列
      Column({ space: 2 }) {
        if (course.hasGrade) {
          Text(course.grade.toFixed(0))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getGradeColor(course.grade))
          if (course.gradePoint >= 0) {
            Text(course.gradePoint.toFixed(1))
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
          }
        } else if (course.credits > 0) {
          Text('进行中')
            .fontSize(10)
            .fontColor('#9E9E9E')
        } else {
          Text('未完结')
            .fontSize(10)
            .fontColor('#FF9800')
        }
      }
      .alignItems(HorizontalAlign.End)
      .padding({ right: 4 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
  }
}

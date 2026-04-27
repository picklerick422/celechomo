// CourseListPage.ets - 课程列表页

import { Semester } from '../../model/Semester';
import { Course } from '../../model/Course';
import { colorFromUid } from '../../model/Period';
import { AppKeys } from '../Index';

@Component
export struct CourseListPage {
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @State semesterId: string = '';
  @State semesterData: Semester | null = null;
  private pathStack: NavPathStack | null = null;

  private syncSemesterData(): void {
    this.semesterData = this.semesters.find(s => s.id === this.semesterId) ?? null;
  }

  private getGradeColor(grade: number): string {
    if (grade >= 90) return '#4CAF50';
    if (grade >= 80) return '#2196F3';
    if (grade >= 60) return '#FF9800';
    return '#F44336';
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部导航栏
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

        // 学期标题 + 统计
        if (this.semesterData !== null && this.semesterData !== undefined) {
          Row() {
            Text(this.semesterData.name)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))

            Blank()

            Text(`${this.semesterData.courses?.length ?? 0} 门课程 · ${this.semesterData.courses?.filter((c: Course) => c.hasGrade).length ?? 0} 门已出分`)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 4 })
        }

        // 课程列表
        if (this.semesterData !== null && this.semesterData !== undefined) {
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.semesterData.courses ?? [], (course: Course) => {
                this.CourseCard(course)
              }, (c: Course) => c.uid)

              Blank().height(80)
            }
            .padding(16)
          }
          .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        } else {
          // 空状态
          Column({ space: 8 }) {
            Text('未找到学期数据')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
            Text('请返回刷新后重试')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as Record<string, string>;
      this.semesterId = params?.['semesterId'] ?? '';
      this.syncSemesterData();
    })
  }

  @Builder
  CourseCard(course: Course) {
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

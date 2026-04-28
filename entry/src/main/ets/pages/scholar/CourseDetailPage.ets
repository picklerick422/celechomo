// CourseDetailPage.ets - 课程详情页

import { Course, Exam, Todo, CourseTimeSlot } from '../../model/Course';
import { Semester } from '../../model/Semester';
import { AppKeys } from '../Index';
import { colorFromUid } from '../../model/Period';

const WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日'];

@Component
export struct CourseDetailPage {
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @StorageProp(AppKeys.HIDE_GPA) hideGpa: boolean = false;
  private pathStack: NavPathStack | null = null;
  @State courseUid: string = '';
  @State semesterId: string = '';

  private get targetSemester(): Semester | null {
    return this.semesters.find(s => s.id === this.semesterId) ?? null;
  }

  private get targetCourse(): Course | null {
    const sem = this.targetSemester;
    if (!sem) return null;

    // 1. 精确 uid 匹配
    const byUid = sem.courses.find(c => c.uid === this.courseUid);
    if (byUid) return byUid;

    // 2. 回退：从 courseUid 中提取课程标识进行匹配
    // uid 格式: course_{标识}_{学期}
    const uidParts = this.courseUid.split('_');
    if (uidParts.length >= 3) {
      // 尝试提取标识部分（去掉前缀 'course' 和最后一段学期ID）
      const possibleId = uidParts.slice(1, -1).join('_');
      const byId = sem.courses.find(c => c.courseId === possibleId);
      if (byId) return byId;

      const byName = sem.courses.find(c => c.name === possibleId);
      if (byName) return byName;
    }

    return null;
  }

  private get courseExams(): Exam[] {
    const sem = this.targetSemester;
    const c = this.targetCourse;
    if (!sem || !c) return [];
    return sem.exams.filter(e => e.courseName === c.name);
  }

  private get courseTodos(): Todo[] {
    const sem = this.targetSemester;
    const c = this.targetCourse;
    if (!sem || !c) return [];
    return sem.todos.filter(t => t.courseName === c.name);
  }

  private fmtGpa(val: number): string {
    if (this.hideGpa) return '***';
    return val > 0 ? val.toFixed(2) : '-';
  }

  private fmtGrade(val: number): string {
    if (this.hideGpa) return '***';
    return val >= 0 ? val.toFixed(0) : '-';
  }

  private getGradeColor(grade: number): ResourceColor {
    if (grade >= 90) return '#4CAF50';
    if (grade >= 80) return '#2196F3';
    if (grade >= 60) return '#FF9800';
    return '#F44336';
  }

  private formatWeeks(weeks: number[]): string {
    if (weeks.length === 0) return '';
    const sorted: number[] = [...weeks].sort((a, b) => a - b);
    const ranges: string[] = [];
    let start = sorted[0];
    let prev = sorted[0];
    for (let i = 1; i <= sorted.length; i++) {
      if (i === sorted.length || sorted[i] !== prev + 1) {
        ranges.push(start === prev ? `${start}` : `${start}-${prev}`);
        if (i < sorted.length) {
          start = sorted[i];
          prev = sorted[i];
        }
      } else {
        prev = sorted[i];
      }
    }
    return `第${ranges.join(', ')}周`;
  }

  private formatSlot(slot: CourseTimeSlot): string {
    const day = WEEKDAYS[(slot.weekDay - 1) % 7];
    const locationStr = slot.location.length > 0 ? ' @ ' + slot.location : '';
    return `周${day} 第${slot.startPeriod}-${slot.endPeriod}节${locationStr}`;
  }

  private formatExamTime(exam: Exam): string {
    const d = exam.startTime;
    const end = exam.endTime;
    const fmt = (n: number) => n.toString().padStart(2, '0');
    return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} ${fmt(d.getHours())}:${fmt(d.getMinutes())} - ${fmt(end.getHours())}:${fmt(end.getMinutes())}`;
  }

  private formatTodoTime(todo: Todo): string {
    const d = todo.dueTime;
    const fmt = (n: number) => n.toString().padStart(2, '0');
    return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} ${fmt(d.getHours())}:${fmt(d.getMinutes())}`;
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

          Text('课程详情')
            .fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)

          Row().width(46)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        Scroll() {
          Column({ space: 12 }) {
            if (this.targetCourse) {
              // 基本信息卡片
              Column({ space: 8 }) {
                Row() {
                  Row()
                    .width(4)
                    .height(48)
                    .borderRadius(2)
                    .backgroundColor(colorFromUid(this.targetCourse.uid))

                  Column({ space: 4 }) {
                    Text(this.targetCourse.name)
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (this.targetCourse.courseId.length > 0) {
                      Text(this.targetCourse.courseId)
                        .fontSize(12)
                        .fontColor($r('app.color.text_tertiary'))
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 10 })
                }
                .width('100%')

                Divider().strokeWidth(0.5).color($r('app.color.progress_bg'))

                Row() {
                  Column({ space: 2 }) {
                    Text('教师').fontSize(11).fontColor($r('app.color.text_tertiary'))
                    Text(this.targetCourse.teacher.length > 0 ? this.targetCourse.teacher : '未知')
                      .fontSize(14).fontColor($r('app.color.text_primary'))
                  }
                  .layoutWeight(1)

                  Column({ space: 2 }) {
                    Text('学分').fontSize(11).fontColor($r('app.color.text_tertiary'))
                    Text(this.targetCourse.credits > 0 ? this.targetCourse.credits.toFixed(1) : '-')
                      .fontSize(14).fontColor($r('app.color.text_primary'))
                  }
                  .layoutWeight(1)

                  Column({ space: 2 }) {
                    Text('学期').fontSize(11).fontColor($r('app.color.text_tertiary'))
                    Text(this.targetSemester?.name ?? this.targetCourse.semester)
                      .fontSize(14).fontColor($r('app.color.text_primary'))
                  }
                  .layoutWeight(1)
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(12)

              // 成绩卡片
              if (this.targetCourse.hasGrade) {
                Column({ space: 8 }) {
                  Text('成绩').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  Row() {
                    Column({ space: 2 }) {
                      Text('分数').fontSize(11).fontColor($r('app.color.text_tertiary'))
                      Text(this.fmtGrade(this.targetCourse.grade))
                        .fontSize(28).fontWeight(FontWeight.Bold)
                        .fontColor(this.getGradeColor(this.targetCourse.grade))
                    }
                    .layoutWeight(1)

                    Column({ space: 2 }) {
                      Text('绩点').fontSize(11).fontColor($r('app.color.text_tertiary'))
                      Text(this.fmtGpa(this.targetCourse.gradePoint))
                        .fontSize(28).fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .layoutWeight(1)

                    Column({ space: 2 }) {
                      Text('等级').fontSize(11).fontColor($r('app.color.text_tertiary'))
                      Text(this.targetCourse.gradeLevel.length > 0 ? this.targetCourse.gradeLevel : '-')
                        .fontSize(28).fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .layoutWeight(1)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(16)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
              }

              // 上课时间卡片
              if (this.targetCourse.timeSlots.length > 0) {
                Column({ space: 8 }) {
                  Text('上课时间').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  ForEach(this.targetCourse.timeSlots, (slot: CourseTimeSlot) => {
                    Row({ space: 8 }) {
                      Text(this.formatSlot(slot))
                        .fontSize(13).fontColor($r('app.color.text_primary'))
                        .layoutWeight(1)
                      Text(this.formatWeeks(slot.weeks))
                        .fontSize(11).fontColor($r('app.color.text_secondary'))
                    }
                    .width('100%')
                  }, (slot: CourseTimeSlot) => `${slot.weekDay}-${slot.startPeriod}-${slot.endPeriod}-${slot.location}`)
                }
                .width('100%')
                .padding(16)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
              }

              // 考试卡片
              if (this.courseExams.length > 0) {
                Column({ space: 8 }) {
                  Text('考试安排').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  ForEach(this.courseExams, (exam: Exam) => {
                    Row({ space: 10 }) {
                      Row()
                        .width(10).height(10)
                        .borderRadius(exam.type === 'midterm' ? 5 : 2)
                        .backgroundColor('#F48FB1')
                      Column({ space: 2 }) {
                        Text(`${exam.type === 'midterm' ? '期中' : '期末'} · ${this.formatExamTime(exam)}`)
                          .fontSize(13).fontColor($r('app.color.text_primary'))
                        if (exam.location.length > 0) {
                          Text(`${exam.location}${exam.seatNo.length > 0 ? ' · 座位 ' + exam.seatNo : ''}`)
                            .fontSize(11).fontColor($r('app.color.text_secondary'))
                        }
                      }
                      .layoutWeight(1)
                    }
                    .width('100%')
                  }, (exam: Exam) => exam.uid)
                }
                .width('100%')
                .padding(16)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
              }

              // 作业卡片
              if (this.courseTodos.length > 0) {
                Column({ space: 8 }) {
                  Text('作业').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  ForEach(this.courseTodos, (todo: Todo) => {
                    Row({ space: 8 }) {
                      Text(todo.title)
                        .fontSize(13).fontColor($r('app.color.text_primary'))
                        .layoutWeight(1)
                      Text(this.formatTodoTime(todo))
                        .fontSize(11).fontColor($r('app.color.text_secondary'))
                    }
                    .width('100%')
                  }, (todo: Todo) => todo.uid)
                }
                .width('100%')
                .padding(16)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
              }
            } else {
              // 课程未找到 — 显示调试信息帮助定位问题
              Column({ space: 8 }) {
                Text('未找到课程信息')
                  .fontSize(16).fontColor($r('app.color.text_secondary'))
                Text('课程可能已被删除或数据未同步')
                  .fontSize(13).fontColor($r('app.color.text_tertiary'))

                Column({ space: 4 }) {
                  Text(`调试: courseUid=${this.courseUid}`)
                    .fontSize(10).fontColor($r('app.color.text_tertiary'))
                  Text(`调试: semesterId=${this.semesterId}`)
                    .fontSize(10).fontColor($r('app.color.text_tertiary'))
                  Text(`调试: semesters=${this.semesters.length}`)
                    .fontSize(10).fontColor($r('app.color.text_tertiary'))
                  Text(`调试: ids=${this.semesters.map(s => s.id).join(',')}`)
                    .fontSize(10).fontColor($r('app.color.text_tertiary'))
                }
                .margin({ top: 12 })
                .padding(12)
                .backgroundColor($r('app.color.progress_bg'))
                .borderRadius(8)
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
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
      const params = ctx.pathInfo.param as Record<string, string>;
      this.courseUid = params?.['courseUid'] ?? '';
      this.semesterId = params?.['semesterId'] ?? '';
      console.info(`[CourseDetailPage] onReady: courseUid=${this.courseUid}, semesterId=${this.semesterId}`);
      console.info(`[CourseDetailPage] semesters count=${this.semesters.length}, ids=${this.semesters.map(s => s.id).join(',')}`);
      const sem = this.targetSemester;
      const course = this.targetCourse;
      console.info(`[CourseDetailPage] targetSemester=${sem?.id ?? 'null'}, targetCourse=${course?.name ?? 'null'}`);
      if (sem) {
        const uids = sem.courses.map(c => `(${c.name}:${c.uid})`).join(', ');
        console.info(`[CourseDetailPage] semester ${sem.id} courses: ${uids}`);
      }
    })
  }
}

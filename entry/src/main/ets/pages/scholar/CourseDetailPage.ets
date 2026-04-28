// CourseDetailPage.ets - 课程详情页

import { Course, Exam, Todo, CourseTimeSlot } from '../../model/Course';
import { Semester } from '../../model/Semester';
import { AppKeys } from '../Index';
import { colorFromUid } from '../../model/Period';
import { StatusBadge } from '../../components/CommonComponents';

const WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日'];

@Component
export struct CourseDetailPage {
  @StorageProp(AppKeys.HIDE_GPA) hideGpa: boolean = false;
  private pathStack: NavPathStack | null = null;

  // 导航参数（由 onReady 设置）
  @State courseUid: string = '';
  @State semesterId: string = '';

  // 预计算的目标数据（由 onReady 一次性查好，build 只负责显示）
  @State hasTargetData: boolean = false;
  @State targetSemesterState: Semester = new Semester();
  @State targetCourseState: Course = new Course();
  @State courseExamsList: Exam[] = [];
  @State courseTodosList: Todo[] = [];

  aboutToAppear(): void {
    // 备份参数读取：防止 NavDestination 实例复用时 onReady 不触发
    const backupUid = AppStorage.get<string>('detailCourseUid');
    const backupSem = AppStorage.get<string>('detailSemesterId');
    if (backupUid && backupUid.length > 0) {
      this.courseUid = backupUid;
    }
    if (backupSem && backupSem.length > 0) {
      this.semesterId = backupSem;
    }
    console.info(`[CourseDetailPage] aboutToAppear: courseUid=${this.courseUid}, semesterId=${this.semesterId}`);
  }

  private resolveTarget(): void {
    const semesters = AppStorage.get<Semester[]>(AppKeys.SEMESTERS) ?? [];
    console.info(`[CourseDetailPage] resolveTarget: semesters=${semesters.length}, courseUid=${this.courseUid}, semesterId=${this.semesterId}`);

    const targetId = this.semesterId.trim();
    let sem: Semester | null = null;
    for (const s of semesters) {
      if ((s.id as string).trim() === targetId) {
        sem = s;
        break;
      }
    }
    this.targetSemesterState = sem ?? new Semester();
    console.info(`[CourseDetailPage] resolveTarget: found semester=${sem !== null ? sem.id : 'null'}`);

    if (!sem) {
      this.targetCourseState = new Course();
      this.hasTargetData = false;
      return;
    }

    // 1. 精确 uid 匹配
    let course = sem.courses.find(c => c.uid === this.courseUid);

    // 2. 回退：从 courseUid 中提取课程标识进行匹配
    if (!course) {
      const uidParts = this.courseUid.split('_');
      if (uidParts.length >= 3) {
        const possibleId = uidParts.slice(1, -1).join('_');
        course = sem.courses.find(c => c.courseId === possibleId);
        if (!course) {
          course = sem.courses.find(c => c.name === possibleId);
        }
      }
    }

    this.targetCourseState = course ?? new Course();
    this.hasTargetData = course !== undefined;
    this.courseExamsList = this.hasTargetData ? this.targetSemesterState.exams.filter(e => e.courseName === this.targetCourseState.name) : [];
    this.courseTodosList = this.hasTargetData ? this.targetSemesterState.todos.filter(t => t.courseName === this.targetCourseState.name) : [];
    console.info(`[CourseDetailPage] resolveTarget: found course=${course !== undefined ? course.name : 'null'}`);
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
            if (this.hasTargetData) {
              // 基本信息卡片
              Column({ space: 8 }) {
                Row() {
                  Row()
                    .width(4)
                    .height(48)
                    .borderRadius(2)
                    .backgroundColor(colorFromUid(this.targetCourseState.uid))

                  Column({ space: 4 }) {
                    Text(this.targetCourseState.name)
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (this.targetCourseState.courseId.length > 0) {
                      Text(this.targetCourseState.courseId)
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
                    Text(this.targetCourseState.teacher.length > 0 ? this.targetCourseState.teacher : '未知')
                      .fontSize(14).fontColor($r('app.color.text_primary'))
                  }
                  .layoutWeight(1)

                  Column({ space: 2 }) {
                    Text('学分').fontSize(11).fontColor($r('app.color.text_tertiary'))
                    Text(this.targetCourseState.credits > 0 ? this.targetCourseState.credits.toFixed(1) : '-')
                      .fontSize(14).fontColor($r('app.color.text_primary'))
                  }
                  .layoutWeight(1)

                  Column({ space: 2 }) {
                    Text('学期').fontSize(11).fontColor($r('app.color.text_tertiary'))
                    Text(this.targetSemesterState.id.length > 0 ? this.targetSemesterState.name : this.targetCourseState.semester)
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
              if (this.targetCourseState.hasGrade) {
                Column({ space: 8 }) {
                  Text('成绩').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  Row() {
                    Column({ space: 2 }) {
                      Text('分数').fontSize(11).fontColor($r('app.color.text_tertiary'))
                      Text(this.fmtGrade(this.targetCourseState.grade))
                        .fontSize(28).fontWeight(FontWeight.Bold)
                        .fontColor(this.getGradeColor(this.targetCourseState.grade))
                    }
                    .layoutWeight(1)

                    Column({ space: 2 }) {
                      Text('绩点').fontSize(11).fontColor($r('app.color.text_tertiary'))
                      Text(this.fmtGpa(this.targetCourseState.gradePoint))
                        .fontSize(28).fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .layoutWeight(1)

                    Column({ space: 2 }) {
                      Text('等级').fontSize(11).fontColor($r('app.color.text_tertiary'))
                      Text(this.targetCourseState.gradeLevel.length > 0 ? this.targetCourseState.gradeLevel : '-')
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
              if (this.targetCourseState.timeSlots.length > 0) {
                Column({ space: 8 }) {
                  Text('上课时间').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  ForEach(this.targetCourseState.timeSlots, (slot: CourseTimeSlot) => {
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
              if (this.courseExamsList.length > 0) {
                Column({ space: 8 }) {
                  Text('考试安排').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  ForEach(this.courseExamsList, (exam: Exam) => {
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
              if (this.courseTodosList.length > 0) {
                Column({ space: 8 }) {
                  Text('作业').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  ForEach(this.courseTodosList, (todo: Todo) => {
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
                  Text(`调试: semesterId=[${this.semesterId}] len=${this.semesterId.length}`)
                    .fontSize(10).fontColor($r('app.color.text_tertiary'))
                  Text(`调试: appStorageLen=${(AppStorage.get<Semester[]>(AppKeys.SEMESTERS) ?? []).length}`)
                    .fontSize(10).fontColor($r('app.color.text_tertiary'))
                  Text(`调试: appStorageIds=${(AppStorage.get<Semester[]>(AppKeys.SEMESTERS) ?? []).map(s => `[${s.id}]`).join(',')}`)
                    .fontSize(10).fontColor($r('app.color.text_tertiary'))
                  Text(`调试: targetSemester=${this.targetSemesterState.id.length > 0 ? this.targetSemesterState.id : 'null'}`)
                    .fontSize(10).fontColor($r('app.color.text_tertiary'))
                  Text(`调试: targetCourse=${this.targetCourseState.uid.length > 0 ? this.targetCourseState.name : 'null'}`)
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
      // 一次性解析目标学期和课程，存入 @State
      this.resolveTarget();
    })
  }
}

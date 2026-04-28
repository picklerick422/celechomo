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

  // ============= UI Builder 方法 =============

  @Builder
  CourseHeaderCard() {
    Column({ space: 16 }) {
      Row({ space: 16 }) {
        Column() {
          Text(this.targetCourseState.name.length > 0 ? this.targetCourseState.name.substring(0, 1) : '?')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width(56)
        .height(56)
        .borderRadius(16)
        .backgroundColor(colorFromUid(this.targetCourseState.uid))
        .justifyContent(FlexAlign.Center)
        .shadow({ radius: 8, color: colorFromUid(this.targetCourseState.uid) + '60', offsetX: 0, offsetY: 4 })

        Column({ space: 6 }) {
          Text(this.targetCourseState.name)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row({ space: 8 }) {
            if (this.targetCourseState.courseId.length > 0) {
              Text(this.targetCourseState.courseId)
                .fontSize(11)
                .fontColor($r('app.color.color_blue'))
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor('#0D007AFF')
                .borderRadius(6)
            }
            if (this.targetCourseState.hasGrade) {
              StatusBadge({ text: '已结课', color: '#8E8E93' })
            } else if (this.targetCourseState.credits > 0) {
              StatusBadge({ text: '进行中', color: '#34C759' })
            } else {
              StatusBadge({ text: '未完结', color: '#FF9500' })
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.progress_bg'))
        .margin({ left: 4, right: 4 })

      Row() {
        Column({ space: 6 }) {
          Row({ space: 4 }) {
            Text('👤')
              .fontSize(12)
            Text('教师')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          Text(this.targetCourseState.teacher.length > 0 ? this.targetCourseState.teacher : '未知')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Divider()
          .width(0.5)
          .height(36)
          .color($r('app.color.progress_bg'))
          .vertical(true)

        Column({ space: 6 }) {
          Row({ space: 4 }) {
            Text('📊')
              .fontSize(12)
            Text('学分')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          Text(this.targetCourseState.credits > 0 ? this.targetCourseState.credits.toFixed(1) : '-')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Divider()
          .width(0.5)
          .height(36)
          .color($r('app.color.progress_bg'))
          .vertical(true)

        Column({ space: 6 }) {
          Row({ space: 4 }) {
            Text('📅')
              .fontSize(12)
            Text('学期')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          Text(this.targetSemesterState.id.length > 0 ? this.targetSemesterState.name : this.targetCourseState.semester)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .shadow({ radius: 12, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
  }

  @Builder
  GradeCard() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Text('🎯')
          .fontSize(16)
        Text('成绩')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Column({ space: 4 }) {
          Text(this.fmtGrade(this.targetCourseState.grade))
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getGradeColor(this.targetCourseState.grade))
          Text('分数')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)

        Divider()
          .width(0.5)
          .height(50)
          .color($r('app.color.progress_bg'))
          .vertical(true)

        Column({ space: 4 }) {
          Text(this.fmtGpa(this.targetCourseState.gradePoint))
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('绩点')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)

        Divider()
          .width(0.5)
          .height(50)
          .color($r('app.color.progress_bg'))
          .vertical(true)

        Column({ space: 4 }) {
          Text(this.targetCourseState.gradeLevel.length > 0 ? this.targetCourseState.gradeLevel : '-')
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('等级')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .shadow({ radius: 12, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
  }

  @Builder
  TimeSlotsCard() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text('⏰')
          .fontSize(16)
        Text('上课时间')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      ForEach(this.targetCourseState.timeSlots, (slot: CourseTimeSlot) => {
        Row({ space: 12 }) {
          Column() {
            Text('🕐')
              .fontSize(18)
          }
          .width(36)
          .height(36)
          .borderRadius(10)
          .backgroundColor('#FFF3E0')
          .justifyContent(FlexAlign.Center)

          Column({ space: 4 }) {
            Text(this.formatSlot(slot))
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(FontWeight.Medium)
            Text(this.formatWeeks(slot.weeks))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#F9F9FB')
        .borderRadius(12)
      }, (slot: CourseTimeSlot) => `${slot.weekDay}-${slot.startPeriod}-${slot.endPeriod}-${slot.location}`)
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .shadow({ radius: 12, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
  }

  @Builder
  ExamsCard() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text('📝')
          .fontSize(16)
        Text('考试安排')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      ForEach(this.courseExamsList, (exam: Exam) => {
        Row({ space: 12 }) {
          Column() {
            Text(exam.type === 'midterm' ? '期中' : '期末')
              .fontSize(11)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium)
          }
          .width(40)
          .height(40)
          .borderRadius(10)
          .backgroundColor(exam.type === 'midterm' ? '#FF9500' : '#FF3B30')
          .justifyContent(FlexAlign.Center)

          Column({ space: 4 }) {
            Text(this.formatExamTime(exam))
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(FontWeight.Medium)
            if (exam.location.length > 0) {
              Text(`${exam.location}${exam.seatNo.length > 0 ? ' · 座位 ' + exam.seatNo : ''}`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#F9F9FB')
        .borderRadius(12)
      }, (exam: Exam) => exam.uid)
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .shadow({ radius: 12, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
  }

  @Builder
  TodosCard() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text('📋')
          .fontSize(16)
        Text('作业')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      ForEach(this.courseTodosList, (todo: Todo) => {
        Row({ space: 12 }) {
          Column() {
            Text('✏️')
              .fontSize(18)
          }
          .width(36)
          .height(36)
          .borderRadius(10)
          .backgroundColor('#E3F2FD')
          .justifyContent(FlexAlign.Center)

          Column({ space: 4 }) {
            Text(todo.title)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.formatTodoTime(todo))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#F9F9FB')
        .borderRadius(12)
      }, (todo: Todo) => todo.uid)
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .shadow({ radius: 12, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
  }

  @Builder
  DebugInfoPanel() {
    Column({ space: 12 }) {
      Text('❓')
        .fontSize(48)
      Text('未找到课程信息')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text('课程可能已被删除或数据未同步')
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))

      Column({ space: 6 }) {
        Text(`调试: courseUid=${this.courseUid}`)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
        Text(`调试: semesterId=[${this.semesterId}] len=${this.semesterId.length}`)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
        Text(`调试: appStorageLen=${(AppStorage.get<Semester[]>(AppKeys.SEMESTERS) ?? []).length}`)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
        Text(`调试: appStorageIds=${(AppStorage.get<Semester[]>(AppKeys.SEMESTERS) ?? []).map(s => `[${s.id}]`).join(',')}`)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
        Text(`调试: targetSemester=${this.targetSemesterState.id.length > 0 ? this.targetSemesterState.id : 'null'}`)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
        Text(`调试: targetCourse=${this.targetCourseState.uid.length > 0 ? this.targetCourseState.name : 'null'}`)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .margin({ top: 16 })
      .padding(16)
      .backgroundColor($r('app.color.progress_bg'))
      .borderRadius(12)
      .width('100%')
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  build() {
    NavDestination() {
      Column() {
        // 导航栏
        Row() {
          Button({ type: ButtonType.Normal }) {
            Image($r('sys.media.ohos_ic_public_arrow_left'))
              .width(24)
              .height(24)
              .fillColor($r('app.color.color_blue'))
          }
          .backgroundColor(Color.Transparent)
          .padding(8)
          .onClick(() => this.pathStack?.pop())

          Text('课程详情')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row()
            .width(40)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        Scroll() {
          Column({ space: 16 }) {
            if (this.hasTargetData) {
              this.CourseHeaderCard()

              if (this.targetCourseState.hasGrade) {
                this.GradeCard()
              }

              if (this.targetCourseState.timeSlots.length > 0) {
                this.TimeSlotsCard()
              }

              if (this.courseExamsList.length > 0) {
                this.ExamsCard()
              }

              if (this.courseTodosList.length > 0) {
                this.TodosCard()
              }
            } else {
              this.DebugInfoPanel()
            }

            Blank().height(80)
          }
          .padding(16)
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as Record<string, string>;
      this.courseUid = params?.['courseUid'] ?? '';
      this.semesterId = params?.['semesterId'] ?? '';
      console.info(`[CourseDetailPage] onReady: courseUid=${this.courseUid}, semesterId=${this.semesterId}`);
      this.resolveTarget();
    })
  }
}

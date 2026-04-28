// Course.ets - 课程/成绩/考试/待办模型

export interface CourseJson {
  uid: string;
  courseId: string;
  name: string;
  shortName: string;
  teacher: string;
  credits: number;
  grade: number;
  gradePoint: number;
  gradeLevel: string;
  semester: string;
  timeSlots: CourseTimeSlot[];
  color: string;
}

export interface ExamJson {
  uid: string;
  courseName: string;
  type: string;
  startTime: string;
  endTime: string;
  location: string;
  seatNo: string;
  semester: string;
}

export interface TodoJson {
  uid: string;
  courseName: string;
  title: string;
  dueTime: string;
  semester: string;
}

export class CourseTimeSlot {
  weekDay: number = 1;       // 1=周一 ~ 7=周日
  startPeriod: number = 1;   // 第几节开始（1-13）
  endPeriod: number = 2;     // 第几节结束
  location: string = '';
  weeks: number[] = [];      // 哪些周上课
  halfType: 'first' | 'second' | 'full' = 'full'; // 所属半学期：first=前半(秋/春), second=后半(冬/夏), full=全学期

  constructor(weekDay: number, startPeriod: number, endPeriod: number,
    location: string, weeks: number[], halfType: 'first' | 'second' | 'full' = 'full') {
    this.weekDay = weekDay;
    this.startPeriod = startPeriod;
    this.endPeriod = endPeriod;
    this.location = location;
    this.weeks = weeks;
    this.halfType = halfType;
  }
}

export class Course {
  uid: string = '';
  courseId: string = '';     // 课程代码
  name: string = '';
  shortName: string = '';
  teacher: string = '';
  credits: number = 2;
  grade: number = -1;        // 百分制，-1=未录入
  gradePoint: number = -1;   // 绩点，-1=未录入
  gradeLevel: string = '';   // 等级 A/B/C...
  semester: string = '';
  timeSlots: CourseTimeSlot[] = [];
  color: string = '#5C9EF8';

  get hasGrade(): boolean {
    return this.grade >= 0;
  }

  toJSON(): CourseJson {
    const result: CourseJson = {
      uid: this.uid,
      courseId: this.courseId,
      name: this.name,
      shortName: this.shortName,
      teacher: this.teacher,
      credits: this.credits,
      grade: this.grade,
      gradePoint: this.gradePoint,
      gradeLevel: this.gradeLevel,
      semester: this.semester,
      timeSlots: this.timeSlots,
      color: this.color
    };
    return result;
  }

  static fromJSON(obj: Record<string, string | number | object>): Course {
    const c = new Course();
    c.uid = (obj['uid'] as string) ?? '';
    c.courseId = (obj['courseId'] as string) ?? '';
    c.name = (obj['name'] as string) ?? '';
    c.shortName = (obj['shortName'] as string) ?? (c.name.slice(0, 4));
    c.teacher = (obj['teacher'] as string) ?? '';
    c.credits = (obj['credits'] as number) ?? 2;
    c.grade = (obj['grade'] as number) ?? -1;
    c.gradePoint = (obj['gradePoint'] as number) ?? -1;
    c.gradeLevel = (obj['gradeLevel'] as string) ?? '';
    c.semester = (obj['semester'] as string) ?? '';
    c.color = (obj['color'] as string) ?? '#5C9EF8';
    // 解析 timeSlots（持久化后恢复需要）
    const slots = (obj['timeSlots'] as Record<string, string | number | boolean | number[]>[]) ?? [];
    c.timeSlots = slots.map(s => {
      // 兼容性处理：旧数据使用 isFirstHalf(boolean)，新数据使用 halfType
      let halfType: 'first' | 'second' | 'full' = 'full';
      const newHalfType = s['halfType'] as string | undefined;
      const oldIsFirstHalf = s['isFirstHalf'] as boolean | undefined;
      if (newHalfType === 'first' || newHalfType === 'second' || newHalfType === 'full') {
        halfType = newHalfType;
      } else if (oldIsFirstHalf !== undefined) {
        halfType = oldIsFirstHalf === true ? 'first' : 'second';
      }
      const slot = new CourseTimeSlot(
        (s['weekDay'] as number) ?? 1,
        (s['startPeriod'] as number) ?? 1,
        (s['endPeriod'] as number) ?? 2,
        (s['location'] as string) ?? '',
        (s['weeks'] as number[]) ?? [],
        halfType
      );
      return slot;
    });
    return c;
  }
}

export class Exam {
  uid: string = '';
  courseName: string = '';
  type: 'midterm' | 'final' = 'final'; // midterm=期中, final=期末
  startTime: Date = new Date();
  endTime: Date = new Date();
  location: string = '';
  seatNo: string = '';
  semester: string = '';

  toJSON(): ExamJson {
    const result: ExamJson = {
      uid: this.uid,
      courseName: this.courseName,
      type: this.type,
      startTime: this.startTime.toISOString(),
      endTime: this.endTime.toISOString(),
      location: this.location,
      seatNo: this.seatNo,
      semester: this.semester
    };
    return result;
  }

  static fromJSON(obj: Record<string, string>): Exam {
    const e = new Exam();
    e.uid = obj['uid'] ?? '';
    e.courseName = obj['courseName'] ?? '';
    e.type = (obj['type'] as 'midterm' | 'final') ?? 'final';
    e.startTime = new Date(obj['startTime'] ?? '');
    e.endTime = new Date(obj['endTime'] ?? '');
    e.location = obj['location'] ?? '';
    e.seatNo = obj['seatNo'] ?? '';
    e.semester = obj['semester'] ?? '';
    return e;
  }
}

export class Todo {
  uid: string = '';
  courseName: string = '';
  title: string = '';
  dueTime: Date = new Date();
  semester: string = '';

  toJSON(): TodoJson {
    const result: TodoJson = {
      uid: this.uid,
      courseName: this.courseName,
      title: this.title,
      dueTime: this.dueTime.toISOString(),
      semester: this.semester
    };
    return result;
  }

  static fromJSON(obj: Record<string, string>): Todo {
    const t = new Todo();
    t.uid = obj['uid'] ?? '';
    t.courseName = obj['courseName'] ?? '';
    t.title = obj['title'] ?? '';
    t.dueTime = new Date(obj['dueTime'] ?? '');
    t.semester = obj['semester'] ?? '';
    return t;
  }
}

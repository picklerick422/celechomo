// Semester.ets - 学期模型

import { Course, Exam, Todo, CourseJson, ExamJson, TodoJson } from './Course';

export interface TimeRangeJson {
  startMinutes: number;
  endMinutes: number;
}

export interface GpaInfoJson {
  fivePointGpa: number;
  fourThreeGpa: number;
  rawFourPointGpa: number;
  percentageGpa: number;
  totalCredits: number;
  majorCredits: number;
  majorGpa: number;
  majorFourGpa: number;
  yearCredits: number;
  yearGpa: number;
  secondCredit: number;
  thirdCredit: number;
  fourthCredit: number;
}

export class GpaInfo {
  fivePointGpa: number = 0;   // 五分制 GPA
  fourThreeGpa: number = 0;   // 4.3 制 GPA
  rawFourPointGpa: number = 0; // 原始四分制
  percentageGpa: number = 0;  // 百分制均分
  totalCredits: number = 0;
  majorCredits: number = 0;
  majorGpa: number = 0;
  majorFourGpa: number = 0;
  yearCredits: number = 0;    // 学年学分
  yearGpa: number = 0;        // 学年均绩
  secondCredit: number = 0;   // 二课分
  thirdCredit: number = 0;    // 三课分
  fourthCredit: number = 0;   // 四课分

  toJSON(): GpaInfoJson {
    const result: GpaInfoJson = {
      fivePointGpa: this.fivePointGpa,
      fourThreeGpa: this.fourThreeGpa,
      rawFourPointGpa: this.rawFourPointGpa,
      percentageGpa: this.percentageGpa,
      totalCredits: this.totalCredits,
      majorCredits: this.majorCredits,
      majorGpa: this.majorGpa,
      majorFourGpa: this.majorFourGpa,
      yearCredits: this.yearCredits,
      yearGpa: this.yearGpa,
      secondCredit: this.secondCredit,
      thirdCredit: this.thirdCredit,
      fourthCredit: this.fourthCredit
    };
    return result;
  }

  static fromJSON(obj: Record<string, number>): GpaInfo {
    const g = new GpaInfo();
    g.fivePointGpa = obj['fivePointGpa'] ?? 0;
    g.fourThreeGpa = obj['fourThreeGpa'] ?? 0;
    g.rawFourPointGpa = obj['rawFourPointGpa'] ?? 0;
    g.percentageGpa = obj['percentageGpa'] ?? 0;
    g.totalCredits = obj['totalCredits'] ?? 0;
    g.majorCredits = obj['majorCredits'] ?? 0;
    g.majorGpa = obj['majorGpa'] ?? 0;
    g.majorFourGpa = obj['majorFourGpa'] ?? 0;
    g.yearCredits = obj['yearCredits'] ?? 0;
    g.yearGpa = obj['yearGpa'] ?? 0;
    g.secondCredit = obj['secondCredit'] ?? 0;
    g.thirdCredit = obj['thirdCredit'] ?? 0;
    g.fourthCredit = obj['fourthCredit'] ?? 0;
    return g;
  }
}

// 课表时间表：第几节 -> [起始时刻, 结束时刻] (小时*60+分钟)
export const PERIOD_TIMES: [number, number][] = [
  [8 * 60, 8 * 60 + 45],      // 第1节
  [8 * 60 + 55, 9 * 60 + 40], // 第2节
  [10 * 60, 10 * 60 + 45],    // 第3节
  [10 * 60 + 55, 11 * 60 + 40], // 第4节
  [13 * 60 + 30, 14 * 60 + 15], // 第5节
  [14 * 60 + 25, 15 * 60 + 10], // 第6节
  [15 * 60 + 30, 16 * 60 + 15], // 第7节
  [16 * 60 + 25, 17 * 60 + 10], // 第8节
  [18 * 60 + 30, 19 * 60 + 15], // 第9节
  [19 * 60 + 25, 20 * 60 + 10], // 第10节
  [20 * 60 + 20, 21 * 60 + 5],  // 第11节
  [21 * 60 + 15, 22 * 60],      // 第12节
  [22 * 60 + 10, 22 * 60 + 55]  // 第13节
];

export interface SemesterJson {
  id: string;
  name: string;
  startDate: string;
  endDate: string;
  totalWeeks: number;
  firstHalfWeeks: number;
  courses: CourseJson[];
  exams: ExamJson[];
  todos: TodoJson[];
  gpaInfo: GpaInfoJson;
}

export class Semester {
  id: string = '';
  name: string = '';        // "2023-2024春"
  startDate: Date = new Date();
  endDate: Date = new Date();
  totalWeeks: number = 20;
  firstHalfWeeks: number = 10; // 前半学期周数
  courses: Course[] = [];
  exams: Exam[] = [];
  todos: Todo[] = [];
  gpaInfo: GpaInfo = new GpaInfo();
  specialDates: Map<string, string> = new Map(); // "YYYY-MM-DD" -> 说明

  get isSpring(): boolean {
    return this.name.includes('春') || this.name.includes('2') || this.name.includes('summer');
  }

  /** 获取当前周次（从1开始，超出返回0） */
  currentWeek(now: Date): number {
    const diff = now.getTime() - this.startDate.getTime();
    if (diff < 0) return 0;
    const week = Math.floor(diff / (7 * 86400000)) + 1;
    return week > this.totalWeeks ? 0 : week;
  }

  /** 获取周次描述 e.g. "春一周" */
  weekLabel(week: number): string {
    const prefix = this.isSpring ? '春' : '秋';
    const half = week <= this.firstHalfWeeks ? '前' : '后';
    return `${prefix}${half}${week}周`;
  }

  toJSON(): SemesterJson {
    const result: SemesterJson = {
      id: this.id,
      name: this.name,
      startDate: this.startDate.toISOString(),
      endDate: this.endDate.toISOString(),
      totalWeeks: this.totalWeeks,
      firstHalfWeeks: this.firstHalfWeeks,
      courses: this.courses.map(c => c.toJSON() as CourseJson),
      exams: this.exams.map(e => e.toJSON() as ExamJson),
      todos: this.todos.map(t => t.toJSON() as TodoJson),
      gpaInfo: this.gpaInfo.toJSON()
    };
    return result;
  }

  static fromJSON(obj: Record<string, string | number | object[]>): Semester {
    const s = new Semester();
    s.id = (obj['id'] as string) ?? '';
    s.name = (obj['name'] as string) ?? '';
    s.startDate = new Date((obj['startDate'] as string) ?? '');
    s.endDate = new Date((obj['endDate'] as string) ?? '');
    s.totalWeeks = (obj['totalWeeks'] as number) ?? 20;
    s.firstHalfWeeks = (obj['firstHalfWeeks'] as number) ?? 10;
    const courses = (obj['courses'] as Record<string, string | number | object>[]) ?? [];
    s.courses = courses.map(c => Course.fromJSON(c as Record<string, string | number | object>));
    const exams = (obj['exams'] as Record<string, string>[]) ?? [];
    s.exams = exams.map(e => Exam.fromJSON(e));
    const todos = (obj['todos'] as Record<string, string>[]) ?? [];
    s.todos = todos.map(t => Todo.fromJSON(t));
    const gpaInfoObj = obj['gpaInfo'];
    if (typeof gpaInfoObj === 'object' && gpaInfoObj !== null && !Array.isArray(gpaInfoObj)) {
      s.gpaInfo = GpaInfo.fromJSON(gpaInfoObj as Record<string, number>);
    }
    return s;
  }
}

/** 时间区间 [开始分钟, 结束分钟]，用于可用工作时段 */
export class TimeRange {
  startMinutes: number = 8 * 60;  // 默认 08:00
  endMinutes: number = 12 * 60;   // 默认 12:00

  constructor(startMinutes?: number, endMinutes?: number) {
    if (startMinutes !== undefined) this.startMinutes = startMinutes;
    if (endMinutes !== undefined) this.endMinutes = endMinutes;
  }

  get label(): string {
    const fmtMin = (m: number) => {
      const h = Math.floor(m / 60).toString().padStart(2, '0');
      const min = (m % 60).toString().padStart(2, '0');
      return `${h}:${min}`;
    };
    return `${fmtMin(this.startMinutes)} - ${fmtMin(this.endMinutes)}`;
  }

  toJSON(): TimeRangeJson {
    const result: TimeRangeJson = { startMinutes: this.startMinutes, endMinutes: this.endMinutes };
    return result;
  }

  static fromJSON(obj: Record<string, number>): TimeRange {
    return new TimeRange(obj['startMinutes'] ?? 8 * 60, obj['endMinutes'] ?? 12 * 60);
  }
}

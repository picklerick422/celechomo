// FlowService.ets - 自动任务调度服务（Flow 时间规划算法）

import { Task, TaskType, TaskStatus, RepeatType } from '../model/Task';
import { Period, PeriodType } from '../model/Period';
import { TimeRange, Semester, PERIOD_TIMES } from '../model/Semester';
import { CourseTimeSlot } from '../model/Course';

const SLOT_MINUTES = 30; // 最小调度单元：30分钟

/**
 * 生成 flowList: 将 DDL 任务自动分配到可用时间段，同时插入课程/考试/固定日程
 * @param tasks 所有任务
 * @param semesters 所有学期（用于提取课程/考试）
 * @param allowTimes 每日可用时间段
 * @param workDuration 工作段时长（分钟）
 * @param restDuration 休息段时长（分钟）
 * @param daysAhead 向前规划天数
 */
export function generateFlowList(
  tasks: Task[],
  semesters: Semester[],
  allowTimes: TimeRange[],
  workDuration: number = 50,
  restDuration: number = 10,
  daysAhead: number = 14
): Period[] {
  const now = new Date();
  const endDate = new Date(now.getTime() + daysAhead * 86400000);
  const periods: Period[] = [];

  // 1. 添加固定日程（课程、考试、用户固定任务）
  const fixedPeriods: Period[] = [];

  // 添加课程 - 展开所有学期所有周次，只保留 [now, endDate] 范围内的
  for (const semester of semesters) {
    // 以学期起始日所在周的周一作为第1周的周一
    const semWeek1Monday = getWeekStart(semester.startDate);

    for (const course of semester.courses) {
      for (const slot of course.timeSlots) {
        for (const week of slot.weeks) {
          // 计算该周周一，再偏移到对应星期几
          const weekMonday = new Date(semWeek1Monday.getTime() + (week - 1) * 7 * 86400000);
          const dayOffset = slot.weekDay - 1; // 0=周一
          const dayDate = new Date(weekMonday.getTime() + dayOffset * 86400000);
          const startTimeParts = minutesToHM(PERIOD_TIMES[slot.startPeriod - 1]?.[0] ?? 480);
          const endTimeParts = minutesToHM(PERIOD_TIMES[slot.endPeriod - 1]?.[1] ?? 525);
          const startTime = new Date(dayDate.getFullYear(), dayDate.getMonth(), dayDate.getDate(),
            startTimeParts[0], startTimeParts[1]);
          const endTime = new Date(dayDate.getFullYear(), dayDate.getMonth(), dayDate.getDate(),
            endTimeParts[0], endTimeParts[1]);
          if (startTime >= now && startTime <= endDate) {
            fixedPeriods.push(new Period(
              `cls_${course.uid}_w${week}_d${slot.weekDay}`,
              course.name,
              startTime,
              endTime,
              PeriodType.CLASSES,
              slot.location,
              course.uid
            ));
          }
        }
      }
    }

    // 添加考试
    for (const exam of semester.exams) {
      if (exam.startTime >= now && exam.startTime <= endDate) {
        fixedPeriods.push(new Period(
          `exam_${exam.uid}`,
          exam.courseName,
          exam.startTime,
          exam.endTime,
          PeriodType.TEST,
          exam.location
        ));
      }
    }
  }

  // 添加用户固定任务
  for (const task of tasks) {
    if (task.type === TaskType.FIXED && task.status !== TaskStatus.DONE) {
      // 处理重复任务
      const taskPeriods = expandFixedTask(task, now, endDate);
      for (const p of taskPeriods) {
        fixedPeriods.push(p);
      }
    }
  }

  // 按时间排序固定日程
  fixedPeriods.sort((a, b) => a.startTime.getTime() - b.startTime.getTime());
  for (const p of fixedPeriods) {
    periods.push(p);
  }

  // 2. 调度 DDL 任务到空闲时间
  const ddlTasks = tasks
    .filter(t =>
      t.type === TaskType.DEADLINE &&
      t.status !== TaskStatus.DONE &&
      t.endTime > now &&
      t.timeNeeded > t.timeSpent
    )
    .sort((a, b) => a.endTime.getTime() - b.endTime.getTime()); // 最紧迫的先排

  for (const task of ddlTasks) {
    let remainingMinutes = task.timeNeeded - task.timeSpent;
    const deadline = task.endTime;

    // 在允许时间内找空闲槽
    let cursor = new Date(now);
    cursor.setSeconds(0, 0);
    // 向上取整到下一个30分钟
    const cursorMins = cursor.getHours() * 60 + cursor.getMinutes();
    const roundedMins = Math.ceil(cursorMins / SLOT_MINUTES) * SLOT_MINUTES;
    cursor.setHours(Math.floor(roundedMins / 60), roundedMins % 60, 0, 0);

    while (remainingMinutes > 0 && cursor < deadline) {
      // 找到当天可用时间段
      const allFixed: Period[] = [];
      for (const p of fixedPeriods) {
        allFixed.push(p);
      }
      for (const p of periods) {
        if (p.type === PeriodType.FLOW) {
          allFixed.push(p);
        }
      }
      const availableSlots = getAvailableSlotsForDay(cursor, allowTimes, allFixed);

      for (const slot of availableSlots) {
        if (remainingMinutes <= 0) break;
        if (slot.start >= deadline) break;

        const slotDuration = Math.min(
          (slot.end.getTime() - slot.start.getTime()) / 60000,
          workDuration,
          remainingMinutes
        );

        if (slotDuration >= SLOT_MINUTES) {
          const flowEnd = new Date(slot.start.getTime() + slotDuration * 60000);
          periods.push(new Period(
            `flow_${task.uid}_${slot.start.getTime()}`,
            task.summary,
            slot.start,
            flowEnd,
            PeriodType.FLOW,
            task.location,
            task.uid
          ));
          remainingMinutes -= slotDuration;
          // 跳过休息时间
          cursor = new Date(flowEnd.getTime() + restDuration * 60000);
        }
      }

      // 移动到第二天
      cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1, 0, 0, 0);
    }
  }

  // 3. 合并所有 periods，按时间排序，只保留未来的
  const allPeriods = periods.filter(p => p.endTime > now);
  allPeriods.sort((a, b) => a.startTime.getTime() - b.startTime.getTime());

  return allPeriods;
}

interface TimeSlot {
  start: Date;
  end: Date;
}

/** 获取某天某允许时间段内的空闲段（排除已占用的 periods） */
function getAvailableSlotsForDay(dayDate: Date, allowTimes: TimeRange[], occupiedPeriods: Period[]): TimeSlot[] {
  const dayStart = new Date(dayDate.getFullYear(), dayDate.getMonth(), dayDate.getDate());
  const available: TimeSlot[] = [];

  for (const range of allowTimes) {
    const rangeStart = new Date(dayStart.getTime() + range.startMinutes * 60000);
    const rangeEnd = new Date(dayStart.getTime() + range.endMinutes * 60000);

    if (rangeEnd <= dayDate) continue; // 已过去
    const start = rangeStart < dayDate ? dayDate : rangeStart;

    // 找出该时间段内已占用的时段
    const occupied = occupiedPeriods
      .filter(p => p.startTime < rangeEnd && p.endTime > start)
      .sort((a, b) => a.startTime.getTime() - b.startTime.getTime());

    let cursor = start;
    for (const occ of occupied) {
      if (occ.startTime > cursor) {
        available.push({ start: cursor, end: occ.startTime });
      }
      if (occ.endTime > cursor) {
        cursor = occ.endTime;
      }
    }
    if (cursor < rangeEnd) {
      available.push({ start: cursor, end: rangeEnd });
    }
  }

  return available.filter(s => (s.end.getTime() - s.start.getTime()) >= SLOT_MINUTES * 60000);
}

/** 展开固定任务（含重复）到多个 Period */
function expandFixedTask(task: Task, from: Date, to: Date): Period[] {
  const periods: Period[] = [];
  const duration = task.endTime.getTime() - task.startTime.getTime();

  // 第一次出现
  if (task.startTime >= from && task.startTime <= to) {
    periods.push(new Period(
      `fixed_${task.uid}`,
      task.summary,
      task.startTime,
      task.endTime,
      PeriodType.USER,
      task.location,
      task.uid
    ));
  }

  // 重复出现
  if (task.repeatType === RepeatType.NONE) return periods;

  let cursor = new Date(task.startTime);
  const repeatEnd = task.repeatEndsTime < to ? task.repeatEndsTime : to;

  let iterations = 0;
  while (iterations < 365) {
    iterations++;
    switch (task.repeatType) {
      case RepeatType.DAILY:
        cursor = new Date(cursor.getTime() + 86400000);
        break;
      case RepeatType.WEEKLY:
        cursor = new Date(cursor.getTime() + 7 * 86400000);
        break;
      case RepeatType.MONTHLY:
        cursor = new Date(cursor.getFullYear(), cursor.getMonth() + 1, cursor.getDate(),
          cursor.getHours(), cursor.getMinutes());
        break;
      case RepeatType.YEARLY:
        cursor = new Date(cursor.getFullYear() + 1, cursor.getMonth(), cursor.getDate(),
          cursor.getHours(), cursor.getMinutes());
        break;
      default:
        return periods;
    }
    if (cursor > repeatEnd) break;
    if (cursor >= from) {
      const endTime = new Date(cursor.getTime() + duration);
      periods.push(new Period(
        `fixed_${task.uid}_${cursor.getTime()}`,
        task.summary,
        cursor,
        endTime,
        PeriodType.USER,
        task.location,
        task.uid
      ));
    }
  }

  return periods;
}

function getWeekStart(date: Date): Date {
  const d = new Date(date);
  const day = d.getDay(); // 0=周日
  const offset = day === 0 ? -6 : 1 - day; // 周一为第一天
  d.setDate(d.getDate() + offset);
  d.setHours(0, 0, 0, 0);
  return d;
}

function minutesToHM(minutes: number): [number, number] {
  return [Math.floor(minutes / 60), minutes % 60];
}

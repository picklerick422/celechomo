// Task.ets - 任务/DDL 模型

export interface TaskJson {
  uid: string;
  summary: string;
  type: string;
  status: string;
  startTime: string;
  endTime: string;
  timeNeeded: number;
  timeSpent: number;
  location: string;
  description: string;
  repeatType: string;
  repeatEndsTime: string;
  blockArrangements: boolean;
  color: string;
}

export enum TaskType {
  DEADLINE = 'deadline', // 有截止时间的 DDL
  FIXED = 'fixed'        // 固定时间日程
}

export enum TaskStatus {
  TODO = 'todo',
  IN_PROGRESS = 'in_progress',
  DONE = 'done',
  EXPIRED = 'expired'
}

export enum RepeatType {
  NONE = 'none',
  DAILY = 'daily',
  WEEKLY = 'weekly',
  MONTHLY = 'monthly',
  YEARLY = 'yearly'
}

export class Task {
  uid: string = '';
  summary: string = '';
  type: TaskType = TaskType.DEADLINE;
  status: TaskStatus = TaskStatus.TODO;
  startTime: Date = new Date();
  endTime: Date = new Date();
  timeNeeded: number = 60;   // 预计用时（分钟）
  timeSpent: number = 0;     // 已用时（分钟）
  location: string = '';
  description: string = '';
  repeatType: RepeatType = RepeatType.NONE;
  repeatEndsTime: Date = new Date();
  blockArrangements: boolean = true; // 阻挡自动安排
  color: string = '#5C9EF8';

  constructor() {
    this.uid = `task_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  }

  get progress(): number {
    if (this.timeNeeded <= 0) return 0;
    return Math.min(1, this.timeSpent / this.timeNeeded);
  }

  /** 计算当前状态 */
  computeStatus(now: Date): TaskStatus {
    if (this.status === TaskStatus.DONE) return TaskStatus.DONE;
    if (this.type === TaskType.FIXED) {
      if (now < this.startTime) return TaskStatus.TODO;
      if (now <= this.endTime) return TaskStatus.IN_PROGRESS;
      return TaskStatus.EXPIRED;
    }
    if (now > this.endTime) return TaskStatus.EXPIRED;
    return this.status;
  }

  /** 状态文字 */
  get statusLabel(): string {
    switch (this.status) {
      case TaskStatus.TODO: return '待办';
      case TaskStatus.IN_PROGRESS: return '进行中';
      case TaskStatus.DONE: return '已完成';
      case TaskStatus.EXPIRED: return '已结束';
      default: return '';
    }
  }

  /** 状态颜色 */
  get statusColor(): string {
    switch (this.status) {
      case TaskStatus.TODO: return '#007AFF';
      case TaskStatus.IN_PROGRESS: return '#FF9500';
      case TaskStatus.DONE: return '#34C759';
      case TaskStatus.EXPIRED: return '#8E8E93';
      default: return '#8E8E93';
    }
  }

  toJSON(): TaskJson {
    const result: TaskJson = {
      uid: this.uid,
      summary: this.summary,
      type: this.type,
      status: this.status,
      startTime: this.startTime.toISOString(),
      endTime: this.endTime.toISOString(),
      timeNeeded: this.timeNeeded,
      timeSpent: this.timeSpent,
      location: this.location,
      description: this.description,
      repeatType: this.repeatType,
      repeatEndsTime: this.repeatEndsTime.toISOString(),
      blockArrangements: this.blockArrangements,
      color: this.color
    };
    return result;
  }

  static fromJSON(obj: Record<string, string | number | boolean>): Task {
    const t = new Task();
    t.uid = (obj['uid'] as string) ?? t.uid;
    t.summary = (obj['summary'] as string) ?? '';
    t.type = (obj['type'] as TaskType) ?? TaskType.DEADLINE;
    t.status = (obj['status'] as TaskStatus) ?? TaskStatus.TODO;
    t.startTime = new Date((obj['startTime'] as string) ?? new Date().toISOString());
    t.endTime = new Date((obj['endTime'] as string) ?? new Date().toISOString());
    t.timeNeeded = (obj['timeNeeded'] as number) ?? 60;
    t.timeSpent = (obj['timeSpent'] as number) ?? 0;
    t.location = (obj['location'] as string) ?? '';
    t.description = (obj['description'] as string) ?? '';
    t.repeatType = (obj['repeatType'] as RepeatType) ?? RepeatType.NONE;
    t.repeatEndsTime = new Date((obj['repeatEndsTime'] as string) ?? new Date().toISOString());
    t.blockArrangements = (obj['blockArrangements'] as boolean) ?? true;
    t.color = (obj['color'] as string) ?? '#5C9EF8';
    return t;
  }

  clone(): Task {
    const json = this.toJSON();
    const record: Record<string, string | number | boolean> = {
      "uid": json.uid,
      "summary": json.summary,
      "type": json.type,
      "status": json.status,
      "startTime": json.startTime,
      "endTime": json.endTime,
      "timeNeeded": json.timeNeeded,
      "timeSpent": json.timeSpent,
      "location": json.location,
      "description": json.description,
      "repeatType": json.repeatType,
      "repeatEndsTime": json.repeatEndsTime,
      "blockArrangements": json.blockArrangements,
      "color": json.color
    };
    return Task.fromJSON(record);
  }
}

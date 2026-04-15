// Period.ets - 事务模型（课程、考试、用户日程、自动安排块）

export enum PeriodType {
  FLOW = 'flow',       // 自动安排的学习块
  TEST = 'test',       // 考试
  CLASSES = 'classes', // 课程
  USER = 'user'        // 用户自定义日程
}

export interface PeriodJson {
  uid: string;
  summary: string;
  location: string;
  startTime: string;
  endTime: string;
  type: PeriodType;
  fromUid: string;
}

export class Period {
  uid: string = '';
  summary: string = '';
  location: string = '';
  startTime: Date = new Date();
  endTime: Date = new Date();
  type: PeriodType = PeriodType.USER;
  fromUid: string = ''; // 关联的 Task UID（flow 类型）

  constructor(uid: string, summary: string, startTime: Date, endTime: Date,
    type: PeriodType, location?: string, fromUid?: string) {
    this.uid = uid;
    this.summary = summary;
    this.startTime = startTime;
    this.endTime = endTime;
    this.type = type;
    this.location = location ?? '';
    this.fromUid = fromUid ?? '';
  }

  /** 是否正在进行中 */
  isOngoing(now: Date): boolean {
    return this.startTime <= now && now <= this.endTime;
  }

  /** 进度 0.0~1.0 */
  progress(now: Date): number {
    const total = this.endTime.getTime() - this.startTime.getTime();
    if (total <= 0) return 1;
    const elapsed = now.getTime() - this.startTime.getTime();
    return Math.min(1, Math.max(0, elapsed / total));
  }

  /** 距开始/结束的秒数 */
  countdownSeconds(now: Date): number {
    if (now < this.startTime) {
      return Math.round((this.startTime.getTime() - now.getTime()) / 1000);
    }
    return Math.round((this.endTime.getTime() - now.getTime()) / 1000);
  }

  toJSON(): PeriodJson {
    const result: PeriodJson = {
      uid: this.uid,
      summary: this.summary,
      location: this.location,
      startTime: this.startTime.toISOString(),
      endTime: this.endTime.toISOString(),
      type: this.type,
      fromUid: this.fromUid
    };
    return result;
  }

  static fromJSON(obj: Record<string, string>): Period {
    return new Period(
      obj['uid'] ?? '',
      obj['summary'] ?? '',
      new Date(obj['startTime'] ?? ''),
      new Date(obj['endTime'] ?? ''),
      (obj['type'] as PeriodType) ?? PeriodType.USER,
      obj['location'] ?? '',
      obj['fromUid'] ?? ''
    );
  }
}

/** 根据 uid 生成稳定颜色 */
export function colorFromUid(uid: string): string {
  const palette: string[] = [
    '#5C9EF8', '#4AC8A8', '#F0A070', '#E87070',
    '#A07EE8', '#70B8E0', '#D4A860', '#70C878'
  ];
  let hash = 0;
  for (let i = 0; i < uid.length; i++) {
    hash = (hash * 31 + uid.charCodeAt(i)) & 0x7FFFFFFF;
  }
  return palette[hash % palette.length];
}

/** 格式化倒计时 HH:MM:SS */
export function formatCountdown(seconds: number): string {
  const abs = Math.abs(seconds);
  const h = Math.floor(abs / 3600);
  const m = Math.floor((abs % 3600) / 60);
  const s = abs % 60;
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${pad(h)}:${pad(m)}:${pad(s)}`;
}

/** 友好的时间描述（基于今天） */
export function friendlyTime(date: Date, now: Date): string {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const diff = Math.round((d.getTime() - today.getTime()) / 86400000);

  const timeStr = `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  if (diff === 0) return `今天 ${timeStr}`;
  if (diff === 1) return `明天 ${timeStr}`;
  if (diff === -1) return `昨天 ${timeStr}`;
  const weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  if (diff > 1 && diff < 7) return `${weekdays[date.getDay()]} ${timeStr}`;
  return `${date.getMonth() + 1}月${date.getDate()}日 ${timeStr}`;
}

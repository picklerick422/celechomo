// StorageService.ets - 本地数据持久化服务

import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { Task } from '../model/Task';
import { Semester, TimeRange } from '../model/Semester';
import { Period } from '../model/Period';

const PREF_NAME = 'celechron_prefs';
const KEY_TASKS = 'tasks';
const KEY_SEMESTERS = 'semesters';
const KEY_FLOW_LIST = 'flow_list';
const KEY_ALLOW_TIMES = 'allow_times';
const KEY_WORK_DURATION = 'work_duration';
const KEY_REST_DURATION = 'rest_duration';
const KEY_GPA_CALC_MODE = 'gpa_calc_mode';
const KEY_HIDE_GPA = 'hide_gpa';
const KEY_SYNC_CALENDAR = 'sync_calendar';
const KEY_IS_GRS = 'is_grs';
const KEY_USERNAME = 'username';
const KEY_THEME_MODE = 'theme_mode';
const KEY_COURSE_MAPPING = 'course_mapping';
const KEY_LAST_UPDATE = 'last_update';
const KEY_PUSH_GRADE = 'push_grade';

let prefInstance: preferences.Preferences | null = null;

async function getPrefs(context: common.UIAbilityContext): Promise<preferences.Preferences> {
  if (!prefInstance) {
    try {
      prefInstance = await preferences.getPreferences(context, PREF_NAME);
    } catch (err) {
      console.error(`getPreferences failed: ${(err as Error).message}`);
      throw new Error(`Failed to get preferences: ${(err as Error).message}`);
    }
  }
  return prefInstance;
}

export class StorageService {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  // ==================== Tasks ====================

  async saveTasks(tasks: Task[]): Promise<void> {
    try {
      const prefs = await getPrefs(this.context);
      await prefs.put(KEY_TASKS, JSON.stringify(tasks.map(t => t.toJSON())));
      await prefs.flush();
    } catch (err) {
      console.error(`saveTasks failed: ${(err as Error).message}`);
    }
  }

  async loadTasks(): Promise<Task[]> {
    try {
      const prefs = await getPrefs(this.context);
      const raw = await prefs.get(KEY_TASKS, '[]') as string;
      const arr = JSON.parse(raw) as Record<string, string | number | boolean>[];
      return arr.map(o => Task.fromJSON(o));
    } catch {
      return [];
    }
  }

  // ==================== Semesters ====================

  async saveSemesters(semesters: Semester[]): Promise<void> {
    try {
      const prefs = await getPrefs(this.context);
      await prefs.put(KEY_SEMESTERS, JSON.stringify(semesters.map(s => s.toJSON())));
      await prefs.flush();
    } catch (err) {
      console.error(`saveSemesters failed: ${(err as Error).message}`);
    }
  }

  async loadSemesters(): Promise<Semester[]> {
    try {
      const prefs = await getPrefs(this.context);
      const raw = await prefs.get(KEY_SEMESTERS, '[]') as string;
      const arr = JSON.parse(raw) as Record<string, string | number | object[]>[];
      return arr.map(o => Semester.fromJSON(o));
    } catch {
      return [];
    }
  }

  // ==================== Flow List ====================

  async saveFlowList(list: Period[]): Promise<void> {
    try {
      const prefs = await getPrefs(this.context);
      await prefs.put(KEY_FLOW_LIST, JSON.stringify(list.map(p => p.toJSON())));
      await prefs.flush();
    } catch (err) {
      console.error(`saveFlowList failed: ${(err as Error).message}`);
    }
  }

  async loadFlowList(): Promise<Period[]> {
    try {
      const prefs = await getPrefs(this.context);
      const raw = await prefs.get(KEY_FLOW_LIST, '[]') as string;
      const arr = JSON.parse(raw) as Record<string, string>[];
      return arr.map(o => Period.fromJSON(o));
    } catch {
      return [];
    }
  }

  // ==================== Settings ====================

  async saveAllowTimes(times: TimeRange[]): Promise<void> {
    try {
      const prefs = await getPrefs(this.context);
      await prefs.put(KEY_ALLOW_TIMES, JSON.stringify(times.map(t => t.toJSON())));
      await prefs.flush();
    } catch (err) {
      console.error(`saveAllowTimes failed: ${(err as Error).message}`);
    }
  }

  async loadAllowTimes(): Promise<TimeRange[]> {
    try {
      const prefs = await getPrefs(this.context);
      const raw = await prefs.get(KEY_ALLOW_TIMES, '[]') as string;
      const arr = JSON.parse(raw) as Record<string, number>[];
      if (arr.length === 0) {
        return [new TimeRange(8 * 60, 12 * 60), new TimeRange(14 * 60, 22 * 60)];
      }
      return arr.map(o => TimeRange.fromJSON(o));
    } catch {
      return [new TimeRange(8 * 60, 12 * 60), new TimeRange(14 * 60, 22 * 60)];
    }
  }

  async saveNumber(key: string, value: number): Promise<void> {
    try {
      const prefs = await getPrefs(this.context);
      await prefs.put(key, value);
      await prefs.flush();
    } catch (err) {
      console.error(`saveNumber ${key} failed: ${(err as Error).message}`);
    }
  }

  async loadNumber(key: string, def: number): Promise<number> {
    try {
      const prefs = await getPrefs(this.context);
      return await prefs.get(key, def) as number;
    } catch {
      return def;
    }
  }

  async saveBoolean(key: string, value: boolean): Promise<void> {
    try {
      const prefs = await getPrefs(this.context);
      await prefs.put(key, value);
      await prefs.flush();
    } catch (err) {
      console.error(`saveBoolean ${key} failed: ${(err as Error).message}`);
    }
  }

  async loadBoolean(key: string, def: boolean): Promise<boolean> {
    try {
      const prefs = await getPrefs(this.context);
      return await prefs.get(key, def) as boolean;
    } catch {
      return def;
    }
  }

  async saveString(key: string, value: string): Promise<void> {
    try {
      const prefs = await getPrefs(this.context);
      await prefs.put(key, value);
      await prefs.flush();
    } catch (err) {
      console.error(`saveString ${key} failed: ${(err as Error).message}`);
    }
  }

  async loadString(key: string, def: string): Promise<string> {
    try {
      const prefs = await getPrefs(this.context);
      return await prefs.get(key, def) as string;
    } catch {
      return def;
    }
  }

  async saveWorkDuration(minutes: number): Promise<void> {
    return this.saveNumber(KEY_WORK_DURATION, minutes);
  }

  async loadWorkDuration(): Promise<number> {
    return this.loadNumber(KEY_WORK_DURATION, 50);
  }

  async saveRestDuration(minutes: number): Promise<void> {
    return this.saveNumber(KEY_REST_DURATION, minutes);
  }

  async loadRestDuration(): Promise<number> {
    return this.loadNumber(KEY_REST_DURATION, 10);
  }

  async saveGpaCalcMode(mode: string): Promise<void> {
    return this.saveString(KEY_GPA_CALC_MODE, mode);
  }

  async loadGpaCalcMode(): Promise<string> {
    return this.loadString(KEY_GPA_CALC_MODE, 'highest');
  }

  async saveHideGpa(hide: boolean): Promise<void> {
    return this.saveBoolean(KEY_HIDE_GPA, hide);
  }

  async loadHideGpa(): Promise<boolean> {
    return this.loadBoolean(KEY_HIDE_GPA, false);
  }

  async saveIsGrs(isGrs: boolean): Promise<void> {
    return this.saveBoolean(KEY_IS_GRS, isGrs);
  }

  async loadIsGrs(): Promise<boolean> {
    return this.loadBoolean(KEY_IS_GRS, false);
  }

  async saveUsername(username: string): Promise<void> {
    return this.saveString(KEY_USERNAME, username);
  }

  async loadUsername(): Promise<string> {
    return this.loadString(KEY_USERNAME, '');
  }

  async saveThemeMode(mode: string): Promise<void> {
    return this.saveString(KEY_THEME_MODE, mode);
  }

  async loadThemeMode(): Promise<string> {
    return this.loadString(KEY_THEME_MODE, 'system');
  }

  async saveLastUpdate(ts: number): Promise<void> {
    return this.saveNumber(KEY_LAST_UPDATE, ts);
  }

  async loadLastUpdate(): Promise<number> {
    return this.loadNumber(KEY_LAST_UPDATE, 0);
  }

  async saveSyncCalendar(enabled: boolean): Promise<void> {
    return this.saveBoolean(KEY_SYNC_CALENDAR, enabled);
  }

  async loadSyncCalendar(): Promise<boolean> {
    return this.loadBoolean(KEY_SYNC_CALENDAR, false);
  }

  async savePushGrade(enabled: boolean): Promise<void> {
    return this.saveBoolean(KEY_PUSH_GRADE, enabled);
  }

  async loadPushGrade(): Promise<boolean> {
    return this.loadBoolean(KEY_PUSH_GRADE, false);
  }

  async saveCourseMapping(mapping: Record<string, string>): Promise<void> {
    return this.saveString(KEY_COURSE_MAPPING, JSON.stringify(mapping));
  }

  async loadCourseMapping(): Promise<Record<string, string>> {
    try {
      const raw = await this.loadString(KEY_COURSE_MAPPING, '{}');
      return JSON.parse(raw) as Record<string, string>;
    } catch {
      return {};
    }
  }

  async clearAll(): Promise<void> {
    try {
      const prefs = await getPrefs(this.context);
      await prefs.clear();
      await prefs.flush();
      prefInstance = null;
    } catch (err) {
      console.error(`clearAll failed: ${(err as Error).message}`);
    }
  }
}

// 常量导出供外部使用
export {
  KEY_WORK_DURATION,
  KEY_REST_DURATION,
  KEY_GPA_CALC_MODE,
  KEY_HIDE_GPA,
  KEY_SYNC_CALENDAR,
  KEY_IS_GRS,
  KEY_USERNAME,
  KEY_THEME_MODE,
  KEY_LAST_UPDATE,
  KEY_PUSH_GRADE
};

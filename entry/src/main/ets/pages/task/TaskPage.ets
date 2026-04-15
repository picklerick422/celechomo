// TaskPage.ets - 任务管理页面（DDL + 固定日程）

import { Task, TaskType, TaskStatus } from '../../model/Task';
import { AppKeys } from '../Index';
import { StorageService } from '../../service/StorageService';
import { generateFlowList } from '../../service/FlowService';
import { TimeRange, Semester } from '../../model/Semester';
import { EmptyView, StatusBadge } from '../../components/CommonComponents';
import common from '@ohos.app.ability.common';
import { promptAction } from '@kit.ArkUI';

// ======================================================
// 任务卡片子组件（需要独立 @State 管理滑动偏移）
// ======================================================
@Component
struct TaskCardView {
  @Prop task: Task = new Task();
  onComplete: () => void = () => {};
  onDelete: () => void = () => {};
  onEdit: () => void = () => {};
  @State swipeOffset: number = 0;

  private formatDeadline(): string {
    const d = this.task.endTime;
    const now = new Date();
    const diffMs = d.getTime() - now.getTime();
    const diffDays = Math.ceil(diffMs / 86400000);
    const timeStr = `${d.getMonth() + 1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
    if (diffDays < 0) return `已过期 ${timeStr}`;
    if (diffDays === 0) return `今天截止 ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
    if (diffDays === 1) return '明天截止';
    return `${diffDays}天后截止 ${timeStr}`;
  }

  private formatFixedTime(): string {
    const d = this.task.startTime;
    const fmtTime = (dt: Date) =>
      `${dt.getHours().toString().padStart(2, '0')}:${dt.getMinutes().toString().padStart(2, '0')}`;
    return `${d.getMonth() + 1}/${d.getDate()} ${fmtTime(d)} - ${fmtTime(this.task.endTime)}`;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 左滑背景（删除 - 红色）
      Row() {
        Blank()
        Column({ space: 6 }) {
          Text('🗑️')
            .fontSize(22)
          Text('删除').fontSize(12).fontColor(Color.White)
        }
        .padding({ right: 28 })
      }
      .width('100%').height('100%')
      .borderRadius(20)
      .backgroundColor($r('app.color.swipe_red'))
      .justifyContent(FlexAlign.End)
      .visibility(this.swipeOffset < -20 ? Visibility.Visible : Visibility.Hidden)

      // 右滑背景（完成/恢复 - 绿色/橙色）
      Row() {
        Column({ space: 6 }) {
          Text(this.task.status === TaskStatus.DONE ? '↩️' : '✓')
            .fontSize(24)
            .fontColor(Color.White)
          Text(this.task.status === TaskStatus.DONE ? '恢复' : '完成').fontSize(12).fontColor(Color.White)
        }
        .padding({ left: 28 })
        Blank()
      }
      .width('100%').height('100%')
      .borderRadius(20)
      .backgroundColor(this.task.status === TaskStatus.DONE ? $r('app.color.swipe_orange') : $r('app.color.swipe_green'))
      .visibility(this.swipeOffset > 20 ? Visibility.Visible : Visibility.Hidden)

      // 卡片主体
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          // 颜色标记
          Row()
            .width(14).height(14)
            .borderRadius(this.task.type === TaskType.FIXED ? 3 : 7)
            .backgroundColor(this.task.color)
            .shadow({
              radius: 4,
              color: this.task.color + '40',
              offsetX: 0,
              offsetY: 2
            })

          Text(this.task.summary)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.task.status === TaskStatus.DONE ? $r('app.color.text_tertiary') : $r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .decoration(this.task.status === TaskStatus.DONE ?
              { type: TextDecorationType.LineThrough } :
              { type: TextDecorationType.None }
            )

          StatusBadge({ text: this.task.statusLabel, color: this.task.statusColor })
        }
        .width('100%')

        // 时间信息
        Row() {
          Text('🕐')
            .fontSize(12)
          Text(this.task.type === TaskType.DEADLINE ? this.formatDeadline() : this.formatFixedTime())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }

        // DDL 进度条
        if (this.task.type === TaskType.DEADLINE && this.task.timeNeeded > 0) {
          Column({ space: 6 }) {
            Row() {
              Blank()
              Text(`${Math.round(this.task.progress * 100)}% 已完成`)
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            Stack() {
              Row()
                .width('100%').height(8).borderRadius(4)
                .backgroundColor($r('app.color.progress_bg'))
              Row()
                .width(`${this.task.progress * 100}%`)
                .height(8).borderRadius(4)
                .backgroundColor(this.task.color)
                .animation({ duration: 500, curve: Curve.EaseOut })
            }
            .width('100%')
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 16, bottom: 16 })
      .borderRadius(20)
      .backgroundColor($r('app.color.card_background'))
      .shadow({
        radius: 12,
        color: '#10000000',
        offsetX: 0,
        offsetY: 4
      })
      .translate({ x: this.swipeOffset })
      .animation({ duration: this.swipeOffset === 0 ? 300 : 0, curve: Curve.EaseOut })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
          .onActionUpdate((event: GestureEvent) => {
            this.swipeOffset = event.offsetX;
          })
          .onActionEnd(() => {
            if (this.swipeOffset < -80) {
              const summary = this.task.summary;
              const onDelete = this.onDelete;
              try {
                this.getUIContext().getPromptAction().showDialog({
                  title: '删除任务',
                  message: `确定要删除"${summary}"吗？`,
                  buttons: [
                    { text: '取消', color: '#000000' },
                    { text: '删除', color: '#FF0000' }
                  ]
                }).then((result) => {
                  if (result.index === 1) {
                    onDelete();
                  }
                });
              } catch {}
            } else if (this.swipeOffset > 80) {
              this.onComplete();
            }
            this.swipeOffset = 0;
          })
      )
    }
    .width('100%')
    .onClick(() => this.onEdit())
  }
}

// ======================================================
// 任务页面主组件
// ======================================================
@Component
export struct TaskPage {
  navPathStack: NavPathStack = new NavPathStack();
  @State tasks: Task[] = [];
  @State semesters: Semester[] = [];
  @State allowTimes: TimeRange[] = [];
  @State workDuration: number = 50;
  @State restDuration: number = 10;
  @State isLoaded: boolean = false;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  private storageService: StorageService | null = null;
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.storageService = new StorageService(context);
    } catch {}
    // 从 AppStorage 读取数据
    this.syncFromAppStorage();
    // 每秒刷新任务状态
    this.refreshTimer = setInterval(() => {
      this.refreshTaskStatuses();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
    }
  }

  private syncFromAppStorage(): void {
    const t = AppStorage.get<Task[]>(AppKeys.TASKS);
    this.tasks = t ?? [];
    const s = AppStorage.get<Semester[]>(AppKeys.SEMESTERS);
    this.semesters = s ?? [];
    const a = AppStorage.get<TimeRange[]>(AppKeys.ALLOW_TIMES);
    this.allowTimes = a ?? [];
    const w = AppStorage.get<number>(AppKeys.WORK_DURATION);
    this.workDuration = w ?? 50;
    const r = AppStorage.get<number>(AppKeys.REST_DURATION);
    this.restDuration = r ?? 10;
    this.isLoaded = true;
  }

  private refreshTaskStatuses(): void {
    const now = new Date();
    const currentTasks = this.tasks;
    if (!currentTasks) return;
    const tasks = [...currentTasks];
    let changed = false;
    for (const task of tasks) {
      const newStatus = task.computeStatus(now);
      if (newStatus !== task.status && task.status !== TaskStatus.DONE) {
        task.status = newStatus;
        changed = true;
      }
    }
    if (changed) {
      this.tasks = tasks;
      AppStorage.set(AppKeys.TASKS, tasks);
    }
  }

  get todoDeadlineTasks(): Task[] {
    const t = this.tasks ?? [];
    if (t.length === 0) return [];
    return t.filter((item: Task) =>
      item.type === TaskType.DEADLINE &&
      item.status !== TaskStatus.DONE &&
      item.status !== TaskStatus.EXPIRED
    ).sort((a: Task, b: Task) => a.endTime.getTime() - b.endTime.getTime()) ?? [];
  }

  get doneDeadlineTasks(): Task[] {
    const t = this.tasks ?? [];
    if (t.length === 0) return [];
    return t.filter((item: Task) =>
      item.type === TaskType.DEADLINE &&
      (item.status === TaskStatus.DONE || item.status === TaskStatus.EXPIRED)
    ).sort((a: Task, b: Task) => b.endTime.getTime() - a.endTime.getTime()) ?? [];
  }

  get fixedTasks(): Task[] {
    const t = this.tasks ?? [];
    if (t.length === 0) return [];
    return t.filter((item: Task) => item.type === TaskType.FIXED)
      .sort((a: Task, b: Task) => a.startTime.getTime() - b.startTime.getTime()) ?? [];
  }

  private async saveAndRebuildFlow(): Promise<void> {
    if (!this.storageService) return;
    const currentTasks = this.tasks;
    if (!currentTasks) return;
    await this.storageService.saveTasks(currentTasks);
    const flowList = generateFlowList(currentTasks, this.semesters ?? [], this.allowTimes ?? [],
      this.workDuration, this.restDuration);
    AppStorage.set(AppKeys.FLOW_LIST, flowList);
    await this.storageService.saveFlowList(flowList);
  }

  private completeTask(uid: string): void {
    const currentTasks = this.tasks;
    if (!currentTasks) return;
    const task = currentTasks.find((item: Task) => item.uid === uid);
    if (!task) return;
    task.status = task.status === TaskStatus.DONE ? TaskStatus.TODO : TaskStatus.DONE;
    this.tasks = [...currentTasks];
    AppStorage.set(AppKeys.TASKS, this.tasks);
    this.saveAndRebuildFlow();
  }

  private deleteTask(uid: string): void {
    const currentTasks = this.tasks;
    if (!currentTasks) return;
    this.tasks = currentTasks.filter((item: Task) => item.uid !== uid);
    AppStorage.set(AppKeys.TASKS, this.tasks);
    this.saveAndRebuildFlow();
  }

  private openTaskEdit(task?: Task): void {
    const param: Record<string, ESObject> = { "task": task ? task.clone() : null } as Record<string, ESObject>;
    this.navPathStack.pushPathByName('TaskEdit', param);
  }

  @Builder
  SectionHeader(title: string, count: number) {
    Row({ space: 10 }) {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(`${count}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor($r('app.color.color_blue'))
    }
    .padding({ left: 4, bottom: 12 })
  }

  build() {
    Column() {
      // 标题栏 - 现代化设计
      Row() {
        Column({ space: 4 }) {
          Text('任务')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.getTaskSummary())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        // 添加按钮 - 渐变风格
        Button({ type: ButtonType.Circle }) {
          Text('+')
            .fontSize(26)
            .fontWeight(300) // Light
            .fontColor(Color.White)
        }
        .width(48).height(48)
        .backgroundColor($r('app.color.color_blue'))
        .shadow({
          radius: 12,
          color: '#40007AFF',
          offsetX: 0,
          offsetY: 6
        })
        .onClick(() => this.openTaskEdit())
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topRectHeight + 10, bottom: 8 })

      Scroll() {
        Column({ space: 0 }) {
          // 待办分组
          if (this.isLoaded && (this.todoDeadlineTasks ?? []).length > 0) {
            Column({ space: 12 }) {
              this.SectionHeader('待办', (this.todoDeadlineTasks ?? []).length)
              ForEach(this.todoDeadlineTasks ?? [], (task: Task) => {
                TaskCardView({
                  task: task,
                  onComplete: () => this.completeTask(task.uid),
                  onDelete: () => this.deleteTask(task.uid),
                  onEdit: () => this.openTaskEdit(task)
                })
              }, (t: Task) => t.uid)
            }
            .padding({ left: 16, right: 16, bottom: 24 })
          }

          // 已完成分组
          if (this.isLoaded && (this.doneDeadlineTasks ?? []).length > 0) {
            Column({ space: 12 }) {
              this.SectionHeader('已完成', (this.doneDeadlineTasks ?? []).slice(0, 10).length)
              ForEach(this.doneDeadlineTasks ?? [].slice(0, 10), (task: Task) => {
                TaskCardView({
                  task: task,

                  onComplete: () => this.completeTask(task.uid),
                  onDelete: () => this.deleteTask(task.uid),
                  onEdit: () => this.openTaskEdit(task)
                })
              }, (t: Task) => t.uid)
            }
            .padding({ left: 16, right: 16, bottom: 24 })
          }

          // 固定日程分组
          if (this.isLoaded && (this.fixedTasks ?? []).length > 0) {
            Column({ space: 12 }) {
              this.SectionHeader('日程', (this.fixedTasks ?? []).length)
              ForEach(this.fixedTasks ?? [], (task: Task) => {
                TaskCardView({
                  task: task,
                  onComplete: () => this.completeTask(task.uid),
                  onDelete: () => this.deleteTask(task.uid),
                  onEdit: () => this.openTaskEdit(task)
                })
              }, (t: Task) => t.uid)
            }
            .padding({ left: 16, right: 16, bottom: 24 })
          }

          // 空状态
          if ((this.tasks ?? []).length === 0) {
            EmptyView({
              icon: '✅',
              title: '没有任务',
              subtitle: '点击右上角"+"添加 DDL 或日程',
              actionText: '添加任务',
              onAction: () => this.openTaskEdit()
            })
          }

          Blank().height(64 + this.bottomRectHeight + 20)
        }
        .padding({ top: 8 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }

  private getTaskSummary(): string {
    const todoCount = (this.tasks ?? []).filter(t =>
      t.status !== TaskStatus.DONE && t.status !== TaskStatus.EXPIRED
    ).length;
    return todoCount > 0 ? `${todoCount} 个待办任务` : '所有任务已完成';
  }
}

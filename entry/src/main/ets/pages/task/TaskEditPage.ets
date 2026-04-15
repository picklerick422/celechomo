// TaskEditPage.ets - 任务编辑页面（NavDestination 模式）

import { Task, TaskType, TaskStatus, RepeatType } from '../../model/Task';
import { AppKeys } from '../Index';
import { StorageService } from '../../service/StorageService';
import { generateFlowList } from '../../service/FlowService';
import { TimeRange, Semester } from '../../model/Semester';
import common from '@ohos.app.ability.common';
import { promptAction } from '@kit.ArkUI';

interface AlertDialogButton {
  value: string;
  fontColor?: Resource;
  action?: () => void;
}

interface RepeatOption {
  label: string;
  value: RepeatType;
}

interface SelectOption {
  value: string;
}

const REPEAT_OPTIONS: RepeatOption[] = [
  { label: '不重复', value: RepeatType.NONE },
  { label: '每天', value: RepeatType.DAILY },
  { label: '每周', value: RepeatType.WEEKLY },
  { label: '每月', value: RepeatType.MONTHLY },
  { label: '每年', value: RepeatType.YEARLY }
];

const TASK_COLORS: string[] = [
  '#5C9EF8', '#4AC8A8', '#F0A070', '#E87070',
  '#A07EE8', '#70B8E0', '#D4A860', '#70C878',
  '#F48FB1', '#CE93D8', '#FFAB91', '#66BB6A'
];

const HOUR_OPTIONS: string[] = (() => {
  const arr: string[] = [];
  for (let i = 0; i < 1000; i++) {
    arr.push(i.toString());
  }
  return arr;
})();

const MINUTE_OPTIONS: string[] = (() => {
  const arr: string[] = [];
  for (let i = 0; i < 60; i++) {
    arr.push(i.toString().padStart(2, '0'));
  }
  return arr;
})();

@Component
export struct TaskEditPage {
  @StorageLink(AppKeys.TASKS) tasks: Task[] = [];
  @StorageLink(AppKeys.SEMESTERS) semesters: Semester[] = [];
  @StorageLink(AppKeys.ALLOW_TIMES) allowTimes: TimeRange[] = [];
  @StorageLink(AppKeys.WORK_DURATION) workDuration: number = 50;
  @StorageLink(AppKeys.REST_DURATION) restDuration: number = 10;

  @State editTask: Task = new Task();
  @State isNew: boolean = true;
  @State taskTypeIndex: number = 0; // 0=截止日程 1=固定日程
  @State timeNeededHours: number = 1;
  @State timeNeededMinutes: number = 0;
  @State showRepeatPicker: boolean = false;
  @State showDeleteConfirm: boolean = false;
  @State showDatePicker: boolean = false;
  @State datePickerIsStart: boolean = true;
  @State datePickerValue: Date = new Date();

  private pathStack: NavPathStack | null = null;
  private storageService: StorageService | null = null;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.storageService = new StorageService(context);
    } catch {}
  }

  private initFromParams(params: Record<string, Object | null>): void {
    const inTask = params?.['task'] as Task | null;
    const isFixed = params?.['isFixed'] as boolean | undefined;

    if (inTask) {
      this.editTask = inTask.clone();
      this.isNew = false;
      this.taskTypeIndex = inTask.type === TaskType.FIXED ? 1 : 0;
      this.timeNeededHours = Math.floor(inTask.timeNeeded / 60);
      this.timeNeededMinutes = inTask.timeNeeded % 60;
    } else {
      this.editTask = new Task();
      this.isNew = true;
      this.taskTypeIndex = isFixed ? 1 : 0;
      this.editTask.type = isFixed ? TaskType.FIXED : TaskType.DEADLINE;
      // 设置默认截止时间为明天同时
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      this.editTask.endTime = tomorrow;
      this.editTask.startTime = tomorrow;
      this.timeNeededHours = 1;
      this.timeNeededMinutes = 0;
    }
  }

  private validateAndSave(): void {
    if (this.editTask.summary.trim().length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '请填写任务名' });
      } catch {}
      return;
    }

    if (this.editTask.type === TaskType.FIXED) {
      if (this.editTask.startTime >= this.editTask.endTime) {
        try {
          this.getUIContext().getPromptAction().showToast({ message: '开始时间必须早于结束时间' });
        } catch {}
        return;
      }
      if (this.editTask.repeatType !== RepeatType.NONE &&
        this.editTask.repeatEndsTime < this.editTask.startTime) {
        try {
          this.getUIContext().getPromptAction().showToast({ message: '重复截止日期必须晚于开始时间' });
        } catch {}
        return;
      }
    } else {
      const timeNeeded = this.timeNeededHours * 60 + this.timeNeededMinutes;
      if (timeNeeded > 999 * 60) {
        try {
          this.getUIContext().getPromptAction().showToast({ message: '预期用时不能超过 999 小时' });
        } catch {}
        return;
      }
      this.editTask.timeNeeded = timeNeeded;
    }

    // 更新任务列表
    if (this.isNew) {
      this.tasks = [...this.tasks, this.editTask];
    } else {
      this.tasks = this.tasks.map(t => t.uid === this.editTask.uid ? this.editTask : t);
    }

    this.saveAndClose();
  }

  private deleteTask(): void {
    this.tasks = this.tasks.filter(t => t.uid !== this.editTask.uid);
    this.saveAndClose();
  }

  private async saveAndClose(): Promise<void> {
    if (!this.storageService) return;
    await this.storageService.saveTasks(this.tasks);
    const flowList = generateFlowList(this.tasks, this.semesters, this.allowTimes,
      this.workDuration, this.restDuration);
    AppStorage.set(AppKeys.FLOW_LIST, flowList);
    await this.storageService.saveFlowList(flowList);
    this.pathStack?.pop();
  }

  private pickDateTime(isStart: boolean): void {
    this.datePickerIsStart = isStart;
    this.datePickerValue = isStart ? this.editTask.startTime : this.editTask.endTime;
    this.showDatePicker = true;
  }

  private onDateAccept(value: Date): void {
    const current = this.datePickerIsStart ? this.editTask.startTime : this.editTask.endTime;
    const updated = new Date(value);
    updated.setHours(current.getHours(), current.getMinutes());
    if (this.datePickerIsStart) {
      this.editTask = this.editTask.clone();
      this.editTask.startTime = updated;
    } else {
      this.editTask = this.editTask.clone();
      this.editTask.endTime = updated;
    }
    this.showDatePicker = false;
  }

  private formatDate(date: Date): string {
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  private getSelectOptions(): SelectOption[] {
    const result: SelectOption[] = [];
    for (let i = 0; i < REPEAT_OPTIONS.length; i++) {
      const opt: SelectOption = { value: REPEAT_OPTIONS[i].label };
      result.push(opt);
    }
    return result;
  }

  build() {
    NavDestination() {
      Column() {
        // 导航栏
        Row() {
          Button({ type: ButtonType.Normal }) {
            Image($r('sys.media.ohos_ic_public_cancel'))
              .width(22).height(22)
              .fillColor($r('app.color.color_blue'))
          }
          .backgroundColor(Color.Transparent)
          .padding(8)
          .onClick(() => this.pathStack?.pop())

          Text(this.isNew ? '新建任务' : '编辑任务')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Button({ type: ButtonType.Normal }) {
            Image($r('sys.media.ohos_ic_public_ok'))
              .width(22).height(22)
              .fillColor($r('app.color.color_blue'))
          }
          .backgroundColor(Color.Transparent)
          .padding(8)
          .onClick(() => this.validateAndSave())
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        Scroll() {
          Column({ space: 16 }) {
            // 类型选择
            Column() {
              Tabs({ index: this.taskTypeIndex }) {
                TabContent().tabBar('截止日程')
                TabContent().tabBar('固定日程')
              }
              .barHeight(40)
              .barMode(BarMode.Fixed)
              .onChange((idx) => {
                this.taskTypeIndex = idx;
                this.editTask.type = idx === 0 ? TaskType.DEADLINE : TaskType.FIXED;
              })
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .padding({ top: 4, bottom: 4 })

            // 任务名
            Column() {
              TextInput({
                text: this.editTask.summary,
                placeholder: '任务名'
              })
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_tertiary'))
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
                .padding(16)
                .onChange((text) => {
                  this.editTask = this.editTask.clone();
                  this.editTask.summary = text;
                })
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)

            // 时间信息
            Column({ space: 0 }) {
              // 开始时间（固定日程）
              if (this.editTask.type === TaskType.FIXED) {
                Row() {
                  Text('开始时间')
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                  Text(this.formatDate(this.editTask.startTime))
                    .fontSize(14)
                    .fontColor($r('app.color.color_blue'))
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .onClick(() => this.pickDateTime(true))

                Divider().strokeWidth(0.5).color($r('app.color.separator')).margin({ left: 16 })
              }

              // 结束/截止时间
              Row() {
                Text(this.editTask.type === TaskType.FIXED ? '结束时间' : '截止时间')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Text(this.formatDate(this.editTask.endTime))
                  .fontSize(14)
                  .fontColor($r('app.color.color_blue'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => this.pickDateTime(false))
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)

            // DDL 专属：预期用时
            if (this.editTask.type === TaskType.DEADLINE) {
              Column() {
                Text('预期用时')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .padding({ left: 16, top: 14, bottom: 8 })
                  .width('100%')
                Row({ space: 16 }) {
                  Column() {
                    Text('小时').fontSize(12).fontColor($r('app.color.text_secondary'))
                    TextPicker({
                      range: HOUR_OPTIONS,
                      value: this.timeNeededHours.toString()
                    })
                      .onChange((value: string | string[]) => {
                        this.timeNeededHours = parseInt(Array.isArray(value) ? value[0] : value);
                      })
                      .height(100)
                  }.layoutWeight(1)

                  Column() {
                    Text('分钟').fontSize(12).fontColor($r('app.color.text_secondary'))
                    TextPicker({
                      range: MINUTE_OPTIONS,
                      value: this.timeNeededMinutes.toString().padStart(2, '0')
                    })
                      .onChange((value: string | string[]) => {
                        this.timeNeededMinutes = parseInt(Array.isArray(value) ? value[0] : value);
                      })
                      .height(100)
                  }.layoutWeight(1)
                }
                .padding({ left: 16, right: 16, bottom: 14 })
              }
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(12)
            }

            // 地点
            Column() {
              TextInput({
                text: this.editTask.location,
                placeholder: '地点（可选）'
              })
                .fontSize(15)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
                .padding(16)
                .onChange((text) => {
                  this.editTask = this.editTask.clone();
                  this.editTask.location = text;
                })
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)

            // 说明
            Column() {
              TextArea({
                text: this.editTask.description,
                placeholder: '说明（可选）'
              })
                .fontSize(15)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
                .height(80)
                .padding(16)
                .onChange((text) => {
                  this.editTask = this.editTask.clone();
                  this.editTask.description = text;
                })
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)

            // 固定日程专属设置
            if (this.editTask.type === TaskType.FIXED) {
              Column({ space: 0 }) {
                // 重复类型
                Row() {
                  Text('重复').fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Select(this.getSelectOptions())
                    .selected(REPEAT_OPTIONS.findIndex(o => o.value === this.editTask.repeatType))
                    .value(REPEAT_OPTIONS.find(o => o.value === this.editTask.repeatType)?.label ?? '不重复')
                    .onSelect((index) => {
                      this.editTask = this.editTask.clone();
                      this.editTask.repeatType = REPEAT_OPTIONS[index].value;
                    })
                    .font({ size: 14 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })

                // 阻挡安排
                Divider().strokeWidth(0.5).color($r('app.color.separator')).margin({ left: 16 })
                Row() {
                  Text('阻挡自动安排').fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.editTask.blockArrangements })
                    .onChange((isOn: boolean) => {
                      this.editTask = this.editTask.clone();
                      this.editTask.blockArrangements = isOn;
                    })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              }
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(12)
            }

            // 颜色选择
            Column({ space: 8 }) {
              Text('颜色标记').fontSize(15).fontColor($r('app.color.text_secondary')).padding({ left: 16, top: 14 })
              Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
                ForEach(TASK_COLORS, (color: string) => {
                  Row()
                    .width(28).height(28)
                    .borderRadius(14)
                    .backgroundColor(color)
                    .border({
                      width: this.editTask.color === color ? 3 : 0,
                      color: Color.White,
                      style: BorderStyle.Solid
                    })
                    .shadow(this.editTask.color === color ?
                      { radius: 4, color: color + '80', offsetX: 0, offsetY: 2 } :
                      { radius: 0, color: Color.Transparent }
                    )
                    .onClick(() => {
                      this.editTask = this.editTask.clone();
                      this.editTask.color = color;
                    })
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 14 })
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)

            // 删除按钮（编辑模式）
            if (!this.isNew) {
              Button('删除任务')
                .width('100%')
                .fontSize(16)
                .fontColor($r('app.color.color_red'))
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
                .padding(16)
                .onClick(() => {
                  const summary = this.editTask.summary;
                  const tasks = this.tasks;
                  const editTaskUid = this.editTask.uid;
                  const pathStack = this.pathStack;
                  const semesters = this.semesters;
                  const allowTimes = this.allowTimes;
                  const workDuration = this.workDuration;
                  const restDuration = this.restDuration;
                  const storageService = this.storageService;
                  try {
                    this.getUIContext().getPromptAction().showDialog({
                      title: '删除任务',
                      message: `确定要删除"${summary}"吗？`,
                      buttons: [
                        { text: '取消', color: '#000000' },
                        { text: '删除', color: '#FF0000' }
                      ]
                    }).then(async (result) => {
                      if (result.index === 1) {
                        const newTasks = tasks.filter((t: Task) => t.uid !== editTaskUid);
                        AppStorage.set(AppKeys.TASKS, newTasks);
                        if (storageService) {
                          await storageService.saveTasks(newTasks);
                          const flowList = generateFlowList(newTasks, semesters, allowTimes, workDuration, restDuration);
                          AppStorage.set(AppKeys.FLOW_LIST, flowList);
                          await storageService.saveFlowList(flowList);
                        }
                        pathStack?.pop();
                      }
                    });
                  } catch {}
                })
            }

            Blank().height(80)
          }
          .padding(16)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // 自定义日期选择器对话框
        if (this.showDatePicker) {
          Stack() {
            Row()
              .width('100%').height('100%')
              .backgroundColor('#80000000')
              .onClick(() => { this.showDatePicker = false; })

            Column({ space: 16 }) {
              Text(this.datePickerIsStart ? '选择开始日期' : '选择结束日期')
                .fontSize(17).fontWeight(FontWeight.Medium)

              DatePicker({
                start: new Date('2020-01-01'),
                end: new Date('2030-12-31'),
                selected: this.datePickerValue
              })
                .onDateChange((value: Date) => {
                  this.datePickerValue = value;
                })
                .height(150)

              Row({ space: 12 }) {
                Button('取消')
                  .layoutWeight(1).backgroundColor($r('app.color.progress_bg'))
                  .fontColor($r('app.color.text_primary'))
                  .onClick(() => { this.showDatePicker = false; })
                Button('确定')
                  .layoutWeight(1).backgroundColor($r('app.color.color_blue'))
                  .fontColor(Color.White)
                  .onClick(() => { this.onDateAccept(this.datePickerValue); })
              }
            }
            .padding(24)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(20)
            .margin({ left: 32, right: 32 })
          }
          .width('100%').height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(100)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as Record<string, Object | null>;
      this.initFromParams(params);
    })
  }
}

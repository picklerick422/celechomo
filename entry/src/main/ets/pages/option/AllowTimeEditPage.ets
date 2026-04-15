// AllowTimeEditPage.ets - 可用工作时段编辑页

import { TimeRange } from '../../model/Semester';
import { AppKeys } from '../Index';
import { StorageService } from '../../service/StorageService';
import common from '@ohos.app.ability.common';
import { promptAction } from '@kit.ArkUI';

@Component
export struct AllowTimeEditPage {
  @StorageLink(AppKeys.ALLOW_TIMES) allowTimes: TimeRange[] = [];
  @State editIndex: number = -1; // -1 = 新建
  @State editStart: number = 8 * 60;
  @State editEnd: number = 12 * 60;
  @State showDialog: boolean = false;
  private pathStack: NavPathStack | null = null;
  private storageService: StorageService | null = null;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.storageService = new StorageService(context);
    } catch {}
  }

  private openAddDialog(): void {
    this.editIndex = -1;
    this.editStart = 8 * 60;
    this.editEnd = 12 * 60;
    this.showDialog = true;
  }

  private openEditDialog(index: number): void {
    this.editIndex = index;
    this.editStart = this.allowTimes[index].startMinutes;
    this.editEnd = this.allowTimes[index].endMinutes;
    this.showDialog = true;
  }

  private saveDialog(): void {
    if (this.editStart >= this.editEnd) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '开始时间必须早于结束时间' });
      } catch {}
      return;
    }

    const newTimes = [...this.allowTimes];
    const newRange = new TimeRange(this.editStart, this.editEnd);

    if (this.editIndex === -1) {
      newTimes.push(newRange);
    } else {
      newTimes[this.editIndex] = newRange;
    }

    newTimes.sort((a, b) => a.startMinutes - b.startMinutes);
    this.allowTimes = newTimes;
    this.storageService?.saveAllowTimes(newTimes);
    this.showDialog = false;
  }

  private deleteTime(index: number): void {
    if (this.allowTimes.length <= 1) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '至少保留一个时段' });
      } catch {}
      return;
    }
    const newTimes = this.allowTimes.filter((_, i) => i !== index);
    this.allowTimes = newTimes;
    this.storageService?.saveAllowTimes(newTimes);
  }

  private minutesToLabel(mins: number): string {
    return `${Math.floor(mins / 60).toString().padStart(2, '0')}:${(mins % 60).toString().padStart(2, '0')}`;
  }

  private generateTimeOptions(): string[] {
    const options: string[] = [];
    for (let h = 0; h < 24; h++) {
      options.push(`${h.toString().padStart(2, '0')}:00`);
      options.push(`${h.toString().padStart(2, '0')}:30`);
    }
    return options;
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

          Text('可用工作时段').fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)

          Row().width(46)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        Scroll() {
          Column({ space: 16 }) {
            Text('自动规划时仅在这些时段安排学习块')
              .fontSize(14).fontColor($r('app.color.text_secondary'))
              .padding({ left: 16, top: 8 })
              .width('100%')

            // 时段列表
            Column({ space: 8 }) {
              ForEach(this.allowTimes, (range: TimeRange, idx: number) => {
                Row({ space: 12 }) {
                  Text(range.label)
                    .fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)

                  Button({ type: ButtonType.Normal }) {
                    Text('编辑').fontSize(14).fontColor($r('app.color.color_blue'))
                  }
                  .backgroundColor(Color.Transparent)
                  .onClick(() => this.openEditDialog(idx))

                  Button({ type: ButtonType.Normal }) {
                    Text('🗑️')
                      .fontSize(16)
                  }
                  .backgroundColor(Color.Transparent)
                  .onClick(() => this.deleteTime(idx))
                }
                .width('100%').padding(16)
                .backgroundColor($r('app.color.card_background')).borderRadius(12)
              })
            }
            .padding({ left: 16, right: 16 })

            // 添加按钮
            Button('添加一个时段')
              .width('100%').fontSize(15)
              .backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.color_blue'))
              .borderRadius(12).padding(16)
              .margin({ left: 16, right: 16 })
              .onClick(() => this.openAddDialog())

            Blank().height(80)
          }
        }
        .layoutWeight(1).scrollBar(BarState.Off)

        // 编辑对话框
        if (this.showDialog) {
          Stack() {
            // 遮罩
            Row()
              .width('100%').height('100%')
              .backgroundColor('#80000000')
              .onClick(() => { this.showDialog = false; })

            // 对话框内容
            Column({ space: 16 }) {
              Text(this.editIndex === -1 ? '添加时段' : '编辑时段')
                .fontSize(17).fontWeight(FontWeight.Medium)

              // 开始时间选择
              Row({ space: 12 }) {
                Text('开始').fontSize(15).fontColor($r('app.color.text_secondary')).width(48)
                TextPicker({
                  range: this.generateTimeOptions(),
                  value: this.minutesToLabel(this.editStart)
                })
                  .onChange((val: string | string[]) => {
                    const v = Array.isArray(val) ? val[0] : val;
                    const parts = v.split(':');
                    this.editStart = parseInt(parts[0]) * 60 + parseInt(parts[1]);
                  })
                  .height(100).layoutWeight(1)
              }

              // 结束时间选择
              Row({ space: 12 }) {
                Text('结束').fontSize(15).fontColor($r('app.color.text_secondary')).width(48)
                TextPicker({
                  range: this.generateTimeOptions(),
                  value: this.minutesToLabel(this.editEnd)
                })
                  .onChange((val: string | string[]) => {
                    const v = Array.isArray(val) ? val[0] : val;
                    const parts = v.split(':');
                    this.editEnd = parseInt(parts[0]) * 60 + parseInt(parts[1]);
                  })
                  .height(100).layoutWeight(1)
              }

              Row({ space: 12 }) {
                Button('取消')
                  .layoutWeight(1).backgroundColor($r('app.color.progress_bg'))
                  .fontColor($r('app.color.text_primary'))
                  .onClick(() => { this.showDialog = false; })
                Button('保存')
                  .layoutWeight(1).backgroundColor($r('app.color.color_blue'))
                  .fontColor(Color.White)
                  .onClick(() => this.saveDialog())
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
      .width('100%').height('100%').backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => { this.pathStack = ctx.pathStack; })
  }
}

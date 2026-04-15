// CourseIdMappingEditPage.ets - 课程代码映射编辑页

import { AppKeys } from '../Index';
import { StorageService } from '../../service/StorageService';
import common from '@ohos.app.ability.common';
import { promptAction } from '@kit.ArkUI';

interface MappingItem {
  originalId: string;
  newId: string;
  note: string;
}

@Component
export struct CourseIdMappingEditPage {
  @State mappings: MappingItem[] = [];
  @State newOriginalId: string = '';
  @State newNewId: string = '';
  @State newNote: string = '';
  private pathStack: NavPathStack | null = null;
  private storageService: StorageService | null = null;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.storageService = new StorageService(context);
    } catch {}
    this.loadMappings();
  }

  private async loadMappings(): Promise<void> {
    const raw = await this.storageService?.loadCourseMapping() ?? {};
    const items: MappingItem[] = [];
    for (const key of Object.keys(raw)) {
      const parts = key.split('|');
      items.push({
        originalId: parts[0] ?? key,
        newId: raw[key],
        note: parts[1] ?? ''
      });
    }
    this.mappings = items;
  }

  private async saveMapping(): Promise<void> {
    const rec: Record<string, string> = {};
    for (const m of this.mappings) {
      rec[`${m.originalId}|${m.note}`] = m.newId;
    }
    await this.storageService?.saveCourseMapping(rec);
  }

  private async addMapping(): Promise<void> {
    if (!this.newOriginalId.trim() || !this.newNewId.trim()) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '请填写原课号和新课号' });
      } catch {}
      return;
    }
    this.mappings = [...this.mappings, {
      originalId: this.newOriginalId.trim(),
      newId: this.newNewId.trim(),
      note: this.newNote.trim()
    }];
    this.newOriginalId = '';
    this.newNewId = '';
    this.newNote = '';
    await this.saveMapping();
  }

  private async deleteMapping(index: number): Promise<void> {
    this.mappings = this.mappings.filter((_, i) => i !== index);
    await this.saveMapping();
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Button({ type: ButtonType.Normal }) {
            Image($r('sys.media.ohos_ic_public_arrow_left'))
              .width(22).height(22).fillColor($r('app.color.color_blue'))
          }
          .backgroundColor(Color.Transparent).padding(8)
          .onClick(() => this.pathStack?.pop())

          Text('课程代码映射').fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)

          Row().width(46)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        Scroll() {
          Column({ space: 16 }) {
            Text('将课程代码替换为另一门课程的代码以合并绩点计算（如重修课）')
              .fontSize(13).fontColor($r('app.color.text_secondary'))
              .padding({ left: 16, right: 16, top: 8 })

            // 现有映射列表
            if (this.mappings.length > 0) {
              Column({ space: 8 }) {
                ForEach(this.mappings, (item: MappingItem, idx: number) => {
                  Row({ space: 12 }) {
                    Column({ space: 4 }) {
                      Text(item.note.length > 0 ? item.note : item.originalId)
                        .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                      Text(`${item.originalId} → ${item.newId}`)
                        .fontSize(12).fontColor($r('app.color.text_secondary'))
                    }
                    .layoutWeight(1).alignItems(HorizontalAlign.Start)

                    Button({ type: ButtonType.Normal }) {
                      Text('🗑️')
                        .fontSize(16)
                    }
                    .backgroundColor(Color.Transparent)
                    .onClick(() => this.deleteMapping(idx))
                  }
                  .width('100%').padding(14)
                  .backgroundColor($r('app.color.card_background')).borderRadius(12)
                }, (m: MappingItem) => m.originalId)
              }
              .padding({ left: 16, right: 16 })
            }

            // 添加表单
            Column({ space: 12 }) {
              Text('添加映射').fontSize(15).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))

              TextInput({ text: this.newOriginalId, placeholder: '原课程代码' })
                .fontSize(15).backgroundColor($r('app.color.app_background'))
                .borderRadius(10).padding(12)
                .onChange((v: string) => { this.newOriginalId = v; })

              TextInput({ text: this.newNewId, placeholder: '新课程代码' })
                .fontSize(15).backgroundColor($r('app.color.app_background'))
                .borderRadius(10).padding(12)
                .onChange((v: string) => { this.newNewId = v; })

              TextInput({ text: this.newNote, placeholder: '备注名（可选）' })
                .fontSize(15).backgroundColor($r('app.color.app_background'))
                .borderRadius(10).padding(12)
                .onChange((v: string) => { this.newNote = v; })

              Button('保存映射')
                .width('100%').fontSize(15)
                .backgroundColor($r('app.color.color_blue')).borderRadius(12)
                .onClick(() => this.addMapping())
            }
            .padding(16)
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
            .margin({ left: 16, right: 16 })

            Blank().height(80)
          }
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => { this.pathStack = ctx.pathStack; })
  }
}

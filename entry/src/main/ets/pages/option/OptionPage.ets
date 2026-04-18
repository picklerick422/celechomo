// OptionPage.ets - 设置主页面

import { AppKeys } from '../Index';
import { StorageService } from '../../service/StorageService';
import { TimeRange } from '../../model/Semester';
import common from '@ohos.app.ability.common';
import { setCookies, setCachedStudentInfo } from '../../service/NetworkService';
import { promptAction } from '@kit.ArkUI';

enum PickerType {
  WorkDuration,
  RestDuration
}

@Component
export struct OptionPage {
  navStack: NavPathStack = new NavPathStack();
  @StorageLink(AppKeys.USERNAME) username: string = '';
  @StorageLink(AppKeys.IS_LOGGED_IN) isLoggedIn: boolean = false;
  @StorageLink(AppKeys.HIDE_GPA) hideGpa: boolean = false;
  @StorageLink(AppKeys.GPA_CALC_MODE) gpaCalcMode: string = 'highest';
  @StorageLink(AppKeys.WORK_DURATION) workDuration: number = 50;
  @StorageLink(AppKeys.REST_DURATION) restDuration: number = 10;
  @StorageLink(AppKeys.ALLOW_TIMES) allowTimes: TimeRange[] = [];
  @StorageLink(AppKeys.LATEST_VERSION) latestVersion: string = '';
  @StorageLink(AppKeys.APP_VERSION) appVersion: string = '1.2.0';
  @StorageLink(AppKeys.SYNC_CALENDAR) syncCalendar: boolean = false;
  @StorageLink(AppKeys.PUSH_GRADE) pushGrade: boolean = false;
  @State showPickerDialog: boolean = false;
  @State pickerTitle: string = '';
  @State pickerOptions: string[] = [];
  @State pickerSelected: number = 0;
  @State pickerType: PickerType = PickerType.WorkDuration;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  private storageService: StorageService | null = null;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.storageService = new StorageService(context);
    } catch {}
  }

  private get hasNewVersion(): boolean {
    return this.latestVersion.length > 0 && this.latestVersion !== this.appVersion;
  }

  private logout(): void {
    const username = this.username;
    const storageService = this.storageService;
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: '退出登录',
        message: `确定要退出 ${username} 的账号吗？`,
        buttons: [
          { text: '取消', color: '#000000' },
          { text: '退出登录', color: '#FF0000' }
        ]
      }).then(async (result) => {
        if (result && (result as promptAction.ShowDialogSuccessResponse).index === 1) {
          setCookies('');
          setCachedStudentInfo(null);
          AppStorage.set(AppKeys.USERNAME, '');
          AppStorage.set(AppKeys.IS_LOGGED_IN, false);
          AppStorage.set(AppKeys.STUDENT_INFO, '');
          await storageService?.saveString('cookies', '');
          await storageService?.saveString('student_info', '');
          await storageService?.saveUsername('');
        }
      }).catch(() => {
        // ignore
      });
    } catch {}
  }

  private showWorkDurationPicker(): void {
    this.pickerTitle = '工作段时长';
    this.pickerOptions = [];
    for (let i = 0; i < 12; i++) {
      this.pickerOptions.push(`${(i + 1) * 5} 分钟`);
    }
    this.pickerSelected = Math.max(0, Math.min(11, Math.round(this.workDuration / 5) - 1));
    this.pickerType = PickerType.WorkDuration;
    this.showPickerDialog = true;
  }

  private showRestDurationPicker(): void {
    this.pickerTitle = '休息段时长';
    this.pickerOptions = [];
    for (let i = 0; i < 12; i++) {
      this.pickerOptions.push(`${(i + 1) * 5} 分钟`);
    }
    this.pickerSelected = Math.max(0, Math.min(11, Math.round(this.restDuration / 5) - 1));
    this.pickerType = PickerType.RestDuration;
    this.showPickerDialog = true;
  }

  private onPickerAccept(selectedIndex: number): void {
    const mins = (selectedIndex + 1) * 5;
    if (this.pickerType === PickerType.WorkDuration) {
      this.workDuration = mins;
      this.storageService?.saveWorkDuration(mins);
    } else {
      this.restDuration = mins;
      this.storageService?.saveRestDuration(mins);
    }
  }

  // -------- 通用 UI 构建块 --------

  @Builder
  SectionLabel(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .fontWeight(FontWeight.Medium)
      .padding({ left: 20, right: 20, top: 24, bottom: 8 })
      .width('100%')
  }

  @Builder
  SepLine() {
    Row()
      .width('100%').height(0.5)
      .backgroundColor($r('app.color.separator'))
      .margin({ left: 56 })
  }

  @Builder
  IconLabel(icon: string, bg: string) {
    Column() {
      Text(icon).fontSize(16)
    }
    .width(36).height(36)
    .borderRadius(10)
    .backgroundColor(bg)
    .justifyContent(FlexAlign.Center)
    .shadow({
      radius: 6,
      color: bg + '40',
      offsetX: 0,
      offsetY: 2
    })
  }

  // -------- 通用设置项行 --------
  @Builder
  SettingsRowModern(icon: string, iconBg: string, title: string, value: string, onTap: () => void) {
    Row({ space: 14 }) {
      this.IconLabel(icon, iconBg)

      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      if (value.length > 0) {
        Text(value)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }

      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(14).height(14).fillColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(onTap)
  }

  // -------- 通用开关行 --------
  @Builder
  SwitchRowModern(icon: string, iconBg: string, title: string, isOn: boolean, onChange: (on: boolean) => void) {
    Row({ space: 14 }) {
      this.IconLabel(icon, iconBg)

      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('app.color.color_blue'))
        .onChange(onChange)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  // -------- 教务分组 --------
  @Builder
  AccountSection() {
    Column() {
      // 登录行
      Row({ space: 14 }) {
        this.IconLabel('🎓', '#4CAF50')
        Text(this.isLoggedIn ? this.username : '点击登录')
          .fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        if (this.isLoggedIn) {
          Button('退出登录')
            .fontSize(12).fontColor($r('app.color.color_red'))
            .backgroundColor('#10FF3B30')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(12)
            .height(32)
            .onClick(() => this.logout())
        } else {
          Image($r('sys.media.ohos_ic_public_arrow_right'))
            .width(14).height(14).fillColor($r('app.color.text_tertiary'))
        }
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => { if (!this.isLoggedIn) this.navStack.pushPathByName('Login', null); })

      this.SepLine()

      // 重修绩点
      Row({ space: 14 }) {
        this.IconLabel('📊', '#00BCD4')
        Text('重修绩点计算').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Select([{ value: '取最高' }, { value: '取首次' }])
          .selected(this.gpaCalcMode === 'highest' ? 0 : 1)
          .value(this.gpaCalcMode === 'highest' ? '取最高' : '取首次')
          .font({ size: 13 })
          .onSelect((idx: number) => {
            const mode = idx === 0 ? 'highest' : 'first';
            this.gpaCalcMode = mode;
            this.storageService?.saveGpaCalcMode(mode);
          })
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })

      this.SepLine()

      // 隐藏绩点
      Row({ space: 14 }) {
        this.IconLabel('🙈', '#FF9500')
        Text('隐藏绩点').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.hideGpa })
          .selectedColor($r('app.color.color_blue'))
          .onChange((on: boolean) => {
            this.hideGpa = on;
            this.storageService?.saveHideGpa(on);
          })
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })

      this.SepLine()

      // 课程代码映射
      Row({ space: 14 }) {
        this.IconLabel('🔧', '#5856D6')
        Text('自定义课程代码映射').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => this.navStack.pushPathByName('CourseIdMapping', null))

      this.SepLine()

      // 推送成绩
      Row({ space: 14 }) {
        this.IconLabel('🔔', '#FF3B30')
        Text('推送成绩变动').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.pushGrade })
          .selectedColor($r('app.color.color_blue'))
          .onChange((on: boolean) => {
            this.pushGrade = on;
            this.storageService?.savePushGrade(on);
          })
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
    }
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .margin({ left: 16, right: 16 })
    .shadow({
      radius: 12,
      color: '#08000000',
      offsetX: 0,
      offsetY: 4
    })
    .clip(true)
  }

  // -------- 时间规划分组 --------
  @Builder
  PlanningSection() {
    Column() {
      Row({ space: 14 }) {
        this.IconLabel('⏱️', '#FF9500')
        Text('工作段时长').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(`${this.workDuration} 分钟`)
          .fontSize(14).fontColor($r('app.color.text_secondary'))
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => this.showWorkDurationPicker())

      this.SepLine()

      Row({ space: 14 }) {
        this.IconLabel('☕', '#5AC8FA')
        Text('休息段时长').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(`${this.restDuration} 分钟`)
          .fontSize(14).fontColor($r('app.color.text_secondary'))
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => this.showRestDurationPicker())

      this.SepLine()

      Row({ space: 14 }) {
        this.IconLabel('🕐', '#34C759')
        Text('可用工作时段').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(`${(this.allowTimes ?? []).length} 个时段`)
          .fontSize(14).fontColor($r('app.color.text_secondary'))
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => this.navStack.pushPathByName('AllowTimeEdit', null))
    }
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .margin({ left: 16, right: 16 })
    .shadow({
      radius: 12,
      color: '#08000000',
      offsetX: 0,
      offsetY: 4
    })
    .clip(true)
  }

  // -------- 日程分组 --------
  @Builder
  ScheduleSection() {
    Column() {
      Row({ space: 14 }) {
        this.IconLabel('📅', '#007AFF')
        Text('同步到系统日历').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.syncCalendar })
          .selectedColor($r('app.color.color_blue'))
          .onChange((on: boolean) => {
            this.syncCalendar = on;
            this.storageService?.saveSyncCalendar(on);
          })
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
    }
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .margin({ left: 16, right: 16 })
    .shadow({
      radius: 12,
      color: '#08000000',
      offsetX: 0,
      offsetY: 4
    })
    .clip(true)
  }

  // -------- 工具分组 --------
  @Builder
  ToolsSection() {
    Column() {
      Row({ space: 14 }) {
        this.IconLabel('⛱️', '#636366')
        Text('外观模式').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text('跟随系统').fontSize(14).fontColor($r('app.color.text_secondary'))
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        const storageService = this.storageService;
        try {
          this.getUIContext().getPromptAction().showDialog({
            title: '外观模式',
            message: '请选择外观模式',
            buttons: [
              { text: '跟随系统', color: '#000000' },
              { text: '浅色模式', color: '#000000' },
              { text: '深色模式', color: '#000000' }
            ]
          }).then((result) => {
            if (result && (result as promptAction.ShowDialogSuccessResponse).index === 0) {
              storageService?.saveThemeMode('system');
            } else if (result && (result as promptAction.ShowDialogSuccessResponse).index === 1) {
              storageService?.saveThemeMode('light');
            } else if (result && (result as promptAction.ShowDialogSuccessResponse).index === 2) {
              storageService?.saveThemeMode('dark');
            }
          }).catch(() => {
            // ignore
          });
        } catch {}
      })

      this.SepLine()

      Row({ space: 14 }) {
        this.IconLabel('💳', '#FF9500')
        Text('付款码').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => this.navStack.pushPathByName('ECardPay', null))
      this.SepLine()

      Row({ space: 14 }) {
        this.IconLabel('🔍', '#5856D6')
        Text('数据诊断').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => this.navStack.pushPathByName('Diagnostic', null))
    }
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .margin({ left: 16, right: 16 })
    .shadow({
      radius: 12,
      color: '#08000000',
      offsetX: 0,
      offsetY: 4
    })
    .clip(true)
  }
  @Builder
  AboutSection() {
    Column() {
      Row({ space: 14 }) {
        this.IconLabel('ℹ️', '#007AFF')
        Text('Celechron').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(`v${this.appVersion}`).fontSize(14).fontColor($r('app.color.text_secondary'))
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => this.navStack.pushPathByName('Credits', null))

      this.SepLine()

      Row({ space: 14 }) {
        this.IconLabel('📋', '#636366')
        Text('服务条款').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => this.navStack.pushPathByName('ServiceTerms', null))

      this.SepLine()

      Row({ space: 14 }) {
        this.IconLabel('🌐', this.hasNewVersion ? '#FF3B30' : '#34C759')
        Text('前往项目网站').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
        if (this.hasNewVersion) {
          Text(`新版本 v${this.latestVersion}`)
            .fontSize(11).fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(10).backgroundColor($r('app.color.color_red'))
        }
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(14).height(14).fillColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
    }
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .margin({ left: 16, right: 16 })
    .shadow({
      radius: 12,
      color: '#08000000',
      offsetX: 0,
      offsetY: 4
    })
    .clip(true)
  }

  build() {
    Column() {
      // 标题栏
      Text('设置')
        .fontSize(28).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .padding({ left: 20, top: this.topRectHeight + 10, bottom: 8 })
        .width('100%')

      Scroll() {
        Column({ space: 0 }) {
          this.SectionLabel('教务')
          this.AccountSection()

          this.SectionLabel('时间规划')
          this.PlanningSection()

          this.SectionLabel('日程')
          this.ScheduleSection()

          this.SectionLabel('工具')
          this.ToolsSection()

          this.SectionLabel('关于')
          this.AboutSection()

          Blank().height(64 + this.bottomRectHeight + 20)
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 自定义选择器对话框 - 现代化样式
      if (this.showPickerDialog) {
        Stack() {
          // 背景遮罩
          Row()
            .width('100%').height('100%')
            .backgroundColor('#80000000')
            .onClick(() => { this.showPickerDialog = false; })

          Column({ space: 20 }) {
            Text(this.pickerTitle)
              .fontSize(18).fontWeight(600) // SemiBold
              .fontColor($r('app.color.text_primary'))

            TextPicker({
              range: this.pickerOptions,
              selected: this.pickerSelected
            })
              .onChange((value: string | string[], index: number | number[]) => {
                const idx = Array.isArray(index) ? index[0] : index;
                this.pickerSelected = idx;
              })
              .height(150)

            Row({ space: 14 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor($r('app.color.progress_bg'))
                .fontColor($r('app.color.text_primary'))
                .borderRadius(14)
                .onClick(() => { this.showPickerDialog = false; })
              Button('确定')
                .layoutWeight(1)
                .backgroundColor($r('app.color.color_blue'))
                .fontColor(Color.White)
                .borderRadius(14)
                .shadow({
                  radius: 8,
                  color: '#30007AFF',
                  offsetX: 0,
                  offsetY: 4
                })
                .onClick(() => {
                  this.onPickerAccept(this.pickerSelected);
                  this.showPickerDialog = false;
                })
            }
          }
          .padding(24)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(24)
          .margin({ left: 24, right: 24 })
          .shadow({
            radius: 24,
            color: '#40000000',
            offsetX: 0,
            offsetY: 8
          })
        }
        .width('100%').height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(100)
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}

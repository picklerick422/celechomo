// CommonComponents.ets - 通用 UI 组件库

import { PeriodType } from '../model/Period';

// ============= RoundRectangleCard =============
// 圆角矩形卡片，白色背景，轻微阴影，支持毛玻璃效果

@Component
export struct RoundRectangleCard {
  @BuilderParam content: () => void = this.defaultContent;
  contentPadding: Padding | Length = { top: 16, bottom: 16, left: 16, right: 16 };
  radius: number = 20;
  enableFrostedGlass: boolean = false;

  @Builder
  defaultContent() {
    Column() {}
  }

  build() {
    Stack() {
      // 毛玻璃背景层（可选）
      if (this.enableFrostedGlass) {
        Column() {}
          .width('100%').height('100%')
          .backgroundColor('#08FFFFFF')
          .backdropBlur(20)
          .borderRadius(this.radius)
      }
      // 主内容层
      Column() {
        this.content()
      }
      .width('100%')
      .padding(this.contentPadding)
      .borderRadius(this.radius)
      .backgroundColor(this.enableFrostedGlass ? '#10FFFFFF' : $r('app.color.card_background'))
      .border({
        width: 0.5,
        color: this.enableFrostedGlass ? '#20FFFFFF' : '#08000000'
      })
    }
    .width('100%')
    .shadow({
      radius: this.enableFrostedGlass ? 16 : 12,
      color: this.enableFrostedGlass ? '#30007AFF' : $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: this.enableFrostedGlass ? 8 : 4
    })
  }
}

// ============= TwoLineCard =============
// 双行信息卡片（上标题，下内容）

@Component
export struct TwoLineCard {
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop animate: boolean = false;
  titleColor: ResourceColor = $r('app.color.text_secondary');
  valueColor: ResourceColor = $r('app.color.text_primary');
  valueFontSize: number = 18;

  build() {
    Column({ space: 4 }) {
      Text(this.title)
        .fontSize(12)
        .fontColor(this.titleColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value)
        .fontSize(this.valueFontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.valueColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .animation(this.animate ? { duration: 300, curve: Curve.EaseOut } : undefined)
  }
}

// ============= SubtitleRow =============
// 分组标题行，可选右侧按钮

@Component
export struct SubtitleRow {
  @Prop title: string = '';
  @Prop actionText: string = '';
  onAction: () => void = () => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Medium)
        .textCase(TextCase.UpperCase)
        .letterSpacing(0.5)
      Blank()
      if (this.actionText.length > 0) {
        Text(this.actionText)
          .fontSize(13)
          .fontColor($r('app.color.color_blue'))
          .onClick(() => this.onAction())
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 4 })
  }
}

// ============= ColorIndicator =============
// 颜色标记点（12×12）

@Component
export struct ColorIndicator {
  @Prop color: string = '#5C9EF8';
  @Prop type: PeriodType = PeriodType.USER;
  indicatorSize: number = 12;

  build() {
    Row()
      .width(this.indicatorSize)
      .height(this.indicatorSize)
      .borderRadius(this.type === PeriodType.TEST ? 2 : this.indicatorSize / 2)
      .backgroundColor(this.color)
  }
}

// ============= StatusBadge =============
// 状态标签徽章

@Component
export struct StatusBadge {
  @Prop text: string = '';
  @Prop color: string = '#007AFF';

  build() {
    Text(this.text)
      .fontSize(11)
      .fontColor(this.color)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(10)
      .backgroundColor(this.color + '20')
  }
}

// ============= RoundRectangleCardWithForehead =============
// 带彩色额头条的圆角卡片，支持渐变效果

@Component
export struct RoundRectangleCardWithForehead {
  @Prop foreheadColor: string = '#00BCD4';
  @Prop title: string = '';
  @BuilderParam content: () => void = this.defaultContent;
  @Prop enableGradient: boolean = true;
  @Prop foreheadEndColor: string = '';

  @Builder
  defaultContent() {
    Column() {}
  }

  // 获取渐变结束颜色（自动计算）
  private getEndColor(): string {
    if (this.foreheadEndColor.length > 0) {
      return this.foreheadEndColor;
    }
    // 自动将颜色变暗/变亮15%作为结束色
    return this.darkenColor(this.foreheadColor, 0.15);
  }

  // 将 HEX 颜色变暗/变亮
  private darkenColor(color: string, factor: number): string {
    if (color.length < 7) return color;
    const r = parseInt(color.substring(1, 3), 16);
    const g = parseInt(color.substring(3, 5), 16);
    const b = parseInt(color.substring(5, 7), 16);
    const nr = Math.max(0, Math.min(255, Math.round(r * (1 - factor))));
    const ng = Math.max(0, Math.min(255, Math.round(g * (1 - factor))));
    const nb = Math.max(0, Math.min(255, Math.round(b * (1 - factor))));
    return `#${nr.toString(16).padStart(2, '0')}${ng.toString(16).padStart(2, '0')}${nb.toString(16).padStart(2, '0')}`;
  }

  build() {
    Column() {
      // 渐变额头条
      Stack() {
        if (this.enableGradient) {
          Row() {
            Column() {}
              .layoutWeight(1).height('100%')
          }
          .width('100%').height('100%')
        }
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }
      .width('100%')
      .height(44)
      .borderRadius({ topLeft: 20, topRight: 20, bottomLeft: 0, bottomRight: 0 })

      // 内容区
      Column() {
        this.content()
      }
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 20, bottomRight: 20 })
    }
    .width('100%')
    .borderRadius(20)
    .shadow({
      radius: 16,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
    .clip(true)
  }
}

// ============= AnimateButton =============
// 带动画反馈的按钮，支持涟漪效果

@Component
export struct AnimateButton {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  @Prop selectedColor: string = '#007AFF';
  onTap: () => void = () => {};
  @State private buttonScale: number = 1;
  @State private isPressed: boolean = false;

  build() {
    Column() {
      Text(this.label)
        .fontSize(14)
        .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selected ? this.selectedColor : $r('app.color.text_secondary'))
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .borderRadius(24)
        .backgroundColor(this.selected ? this.selectedColor + '15' :
          (this.isPressed ? $r('app.color.progress_bg') : Color.Transparent))
        .scale({ x: this.buttonScale, y: this.buttonScale })
        .shadow(this.isPressed ? {
          radius: 6,
          color: '#10000000',
          offsetX: 0,
          offsetY: 2
        } : {
          radius: 0,
          color: '#00000000',
          offsetX: 0,
          offsetY: 0
        })
        .animation({
          duration: this.isPressed ? 100 : 200,
          curve: this.isPressed ? Curve.EaseOut : Curve.EaseInOut
        })
    }
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true;
        this.buttonScale = 0.95;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false;
        this.buttonScale = 1;
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}

// ============= LoadingView =============
// 加载中视图

@Component
export struct LoadingView {
  @Prop message: string = '加载中...';

  build() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('app.color.color_blue'))
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

// ============= EmptyView =============
// 空状态视图，支持毛玻璃效果

@Component
export struct EmptyView {
  @Prop icon: string = '📭';
  @Prop title: string = '暂无数据';
  @Prop subtitle: string = '';
  @Prop actionText: string = '';
  onAction: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      // 动态图标
      Column() {
        Text(this.icon)
          .fontSize(56)
          .fontWeight(300) // Light
      }
      .width(100)
      .height(100)
      .borderRadius(50)
      .backgroundColor($r('app.color.progress_bg'))
      .justifyContent(FlexAlign.Center)
      .shadow({
        radius: 12,
        color: '#20000000',
        offsetX: 0,
        offsetY: 4
      })

      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32 })
      }
      if (this.actionText.length > 0) {
        Button(this.actionText)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.color_blue'))
          .borderRadius(12)
          .shadow({
            radius: 8,
            color: '#30007AFF',
            offsetX: 0,
            offsetY: 4
          })
          .margin({ top: 8 })
          .onClick(() => this.onAction())
      }
    }
    .width('100%')
    .padding({ top: 80, bottom: 40 })
    .alignItems(HorizontalAlign.Center)
  }
}

// ============= SectionDivider =============
// 分组分隔线

@Component
export struct SectionDivider {
  build() {
    Divider()
      .width('100%')
      .strokeWidth(0.5)
      .color($r('app.color.separator'))
      .margin({ left: 16 })
  }
}

// ============= SettingsRow =============
// 设置项行

@Component
export struct SettingsRow {
  @Prop icon: string = '';
  @Prop iconColor: string = '#007AFF';
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop showArrow: boolean = true;
  @BuilderParam trailing: () => void = this.defaultTrailing;
  onTap: () => void = () => {};

  @Builder
  defaultTrailing() {
    Column() {}
  }

  build() {
    Row({ space: 12 }) {
      if (this.icon.length > 0) {
        Row() {
          Text(this.icon)
            .fontSize(16)
        }
        .width(32)
        .height(32)
        .borderRadius(8)
        .backgroundColor(this.iconColor)
        .justifyContent(FlexAlign.Center)
      }

      Text(this.title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      this.trailing()

      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }

      if (this.showArrow) {
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => this.onTap())
  }
}

// ============= SearchBar =============
// 搜索栏组件

@Component
export struct SearchBar {
  @Prop placeholder: string = '搜索...';
  @Prop value: string = '';
  @Prop disabled: boolean = false;
  onChange: (text: string) => void = () => {};
  onFocusCallback: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Text('🔍')
        .fontSize(16)

      TextInput({ text: this.value, placeholder: this.placeholder })
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .border({ width: 0 })
        .layoutWeight(1)
        .enabled(!this.disabled)
        .onChange((text: string) => this.onChange(text))
        .onFocus(() => this.onFocusCallback())
    }
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor($r('app.color.progress_bg'))
    .width('100%')
  }
}

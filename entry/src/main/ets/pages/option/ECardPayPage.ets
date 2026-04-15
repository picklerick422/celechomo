// ECardPayPage.ets - 付款码页面

import { fetchPaymentCode } from '../../service/NetworkService';
import promptAction from '@ohos.promptAction';

@Component
export struct ECardPayPage {
  @State paymentCode: string = '';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  private pathStack: NavPathStack | null = null;

  aboutToAppear(): void {
    this.loadPaymentCode();
  }

  private async loadPaymentCode(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';

    const result = await fetchPaymentCode();
    if (result.success && result.data) {
      this.paymentCode = result.data;
    } else {
      this.errorMessage = result.message;
    }
    this.isLoading = false;
  }

  /** 判断是否显示 QR（短码用 QR，长码显示文字条码） */
  private get isQrCode(): boolean {
    return this.paymentCode.length < 30;
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

          Text('付款码').fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)

          Row().width(46)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        Column({ space: 32 }) {
          if (this.isLoading) {
            Column({ space: 16 }) {
              LoadingProgress().width(48).height(48).color($r('app.color.color_blue'))
              Text('正在获取付款码...').fontSize(14).fontColor($r('app.color.text_secondary'))
            }
            .padding({ top: 80 })
          } else if (this.errorMessage.length > 0) {
            Column({ space: 16 }) {
              Text('❌').fontSize(48)
              Text(this.errorMessage).fontSize(14).fontColor($r('app.color.color_red'))
                .textAlign(TextAlign.Center).padding({ left: 32, right: 32 })
              Button('重新获取')
                .fontSize(15).backgroundColor($r('app.color.color_blue')).borderRadius(12)
                .onClick(() => this.loadPaymentCode())
            }
            .padding({ top: 60 })
          } else if (this.paymentCode.length > 0) {
            // 二维码显示区域
            Column({ space: 20 }) {
              // 使用 QRCode 组件
              if (this.isQrCode) {
                QRCode(this.paymentCode)
                  .width(220).height(220)
                  .color(Color.Black)
                  .backgroundColor(Color.White)
              } else {
                // 长条码显示
                Column() {
                  Text(this.paymentCode)
                    .fontSize(20).fontWeight(FontWeight.Bold)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.text_primary'))
                    .textAlign(TextAlign.Center)
                    .letterSpacing(3)
                }
                .width(280).height(80)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(12)
                .justifyContent(FlexAlign.Center)
                .shadow({ radius: 8, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 2 })
              }

              Text(`付款码：${this.paymentCode}`)
                .fontSize(14).fontColor($r('app.color.text_secondary'))

              Button('刷新二维码')
                .fontSize(15)
                .backgroundColor($r('app.color.color_blue'))
                .borderRadius(20)
                .padding({ left: 32, right: 32, top: 12, bottom: 12 })
                .onClick(() => this.loadPaymentCode())
            }
            .padding({ top: 40 })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%').height('100%').backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => { this.pathStack = ctx.pathStack; })
  }
}

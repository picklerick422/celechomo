// ServiceTermsPage.ets - 服务条款页面

@Component
export struct ServiceTermsPage {
  private pathStack: NavPathStack | null = null;

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

          Text('服务条款').fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)

          Row().width(46)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        Scroll() {
          Text(this.getTermsText())
            .fontSize(14).fontColor($r('app.color.text_primary'))
            .lineHeight(22)
            .padding({ left: 20, right: 20, top: 16, bottom: 80 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor($r('app.color.app_background'))
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => { this.pathStack = ctx.pathStack; })
  }

  private getTermsText(): string {
    return `Celechron 服务条款

最后更新日期：2024年1月1日

一、服务说明

Celechron 是一款面向在校学生的第三方学业管理工具，提供课程查询、成绩浏览、DDL管理等功能。本应用与学校官方无关联关系。

二、用户数据

1. 您的学号和密码仅用于登录学校教务系统，不会被上传至任何第三方服务器。
2. 所有学业数据存储在您的设备本地，不会被分享给第三方。
3. 您可以随时在设置中退出登录并清除所有数据。

三、免责声明

1. 本应用展示的数据来源于学校教务系统，如有出入请以官方为准。
2. 本应用不保证数据的实时性和准确性。
3. 用户因使用本应用导致的任何损失，开发者不承担责任。

四、开源协议

本应用基于 GNU General Public License v3 开源。您可以在 GitHub 上查看和参与项目。

如有疑问，请通过 GitHub Issues 联系我们。`;
  }
}

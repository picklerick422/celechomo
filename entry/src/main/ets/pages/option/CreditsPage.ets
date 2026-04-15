// CreditsPage.ets - 关于页面

import http from '@ohos.net.http';
import { AppKeys } from '../Index';

interface GitHubUser {
  login: string;
}

@Component
export struct CreditsPage {
  @StorageLink(AppKeys.APP_VERSION) appVersion: string = '1.2.0';
  @State developers: string[] = ['Loading...'];
  private pathStack: NavPathStack | null = null;

  aboutToAppear(): void {
    this.fetchDevelopers();
  }

  private async fetchDevelopers(): Promise<void> {
    try {
      const req = http.createHttp();
      const resp = await req.request('https://api.github.com/repos/Celechron/Celechron/contributors', {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/vnd.github.v3+json' },
        connectTimeout: 8000, readTimeout: 8000
      });
      req.destroy();
      if (resp.responseCode === 200) {
        const list = JSON.parse(resp.result as string) as Array<GitHubUser>;
        this.developers = list.map(u => u.login);
      }
    } catch {
      this.developers = ['Celechron Team'];
    }
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

          Text('关于').fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)

          Row().width(46)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        Scroll() {
          Column({ space: 24 }) {
            // App 信息
            Column({ space: 12 }) {
              // Logo 占位
              Row()
                .width(108).height(108)
                .borderRadius(24)
                .backgroundColor($r('app.color.color_blue'))
                .justifyContent(FlexAlign.Center)
                .margin({ top: 32 })

              Text('Celechron')
                .fontSize(32).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text(`v${this.appVersion}`)
                .fontSize(12).fontColor($r('app.color.text_tertiary'))
            }
            .alignItems(HorizontalAlign.Center)

            // 制作人员
            Column({ space: 8 }) {
              Text('制作人员').fontSize(13).fontColor($r('app.color.text_secondary'))
                .padding({ left: 16, bottom: 4 }).width('100%')

              Column({ space: 0 }) {
                // 设计
                Row() {
                  Text('设计').fontSize(15).fontColor($r('app.color.text_secondary'))
                    .width(60)
                  Text('Celechron Design Team').fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                }
                .padding(16)

                Divider().strokeWidth(0.5).color($r('app.color.separator')).margin({ left: 16 })

                // 开发
                Row({ space: 8 }) {
                  Text('开发').fontSize(15).fontColor($r('app.color.text_secondary'))
                    .width(60)
                  Column({ space: 4 }) {
                    ForEach(this.developers, (dev: string) => {
                      Text(dev).fontSize(15).fontColor($r('app.color.text_primary'))
                    })
                  }.alignItems(HorizontalAlign.Start)
                }
                .padding(16)
              }
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(16).margin({ left: 16, right: 16 })
            }

            // 开源协议
            Column({ space: 8 }) {
              Text('开源信息').fontSize(13).fontColor($r('app.color.text_secondary'))
                .padding({ left: 16, bottom: 4 }).width('100%')

              Column({ space: 0 }) {
                Row() {
                  Text('开源协议').fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Text('GNU GPL v3').fontSize(14).fontColor($r('app.color.text_secondary'))
                }
                .padding(16)

                Divider().strokeWidth(0.5).color($r('app.color.separator')).margin({ left: 16 })

                Row() {
                  Text('ICP 备案').fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Text('浙ICP备XXXXXXXX号').fontSize(14).fontColor($r('app.color.text_secondary'))
                }
                .padding(16)

                Divider().strokeWidth(0.5).color($r('app.color.separator')).margin({ left: 16 })

                Row() {
                  Text('项目地址').fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Text('GitHub').fontSize(14).fontColor($r('app.color.color_blue'))
                }
                .padding(16)
              }
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(16).margin({ left: 16, right: 16 })
            }

            Text('本应用仅供学习交流，与学校官方无关。\n数据来源于学校教务系统，请以官方为准。')
              .fontSize(12).fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center).padding({ left: 32, right: 32 })

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

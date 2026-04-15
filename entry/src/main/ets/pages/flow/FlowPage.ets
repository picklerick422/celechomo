// FlowPage.ets - 接下来页面（时间流）

import { Period, PeriodType, colorFromUid, formatCountdown, friendlyTime } from '../../model/Period';
import { AppKeys } from '../Index';
import { ColorIndicator, RoundRectangleCard, EmptyView } from '../../components/CommonComponents';
import curves from '@ohos.curves';

interface CourseScheduleParam {
  courseUid: string;
}

// 获取渐变颜色的结束色（自动计算）
function getGradientEndColor(color: string): string {
  if (color.length < 7) return color;
  const r = parseInt(color.substring(1, 3), 16);
  const g = parseInt(color.substring(3, 5), 16);
  const b = parseInt(color.substring(5, 7), 16);
  const factor = 0.2;
  const nr = Math.max(0, Math.min(255, Math.round(r * (1 - factor))));
  const ng = Math.max(0, Math.min(255, Math.round(g * (1 - factor))));
  const nb = Math.max(0, Math.min(255, Math.round(b * (1 - factor))));
  return `#${nr.toString(16).padStart(2, '0')}${ng.toString(16).padStart(2, '0')}${nb.toString(16).padStart(2, '0')}`;
}

@Component
export struct FlowPage {
  navStack: NavPathStack = new NavPathStack();
  @StorageLink(AppKeys.FLOW_LIST) flowList: Period[] = [];
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @State currentTime: Date = new Date();
  private timer: number = -1;
  @State progressValues: number[] = [];

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private updateTime(): void {
    this.currentTime = new Date();
    this.refreshCurrentPeriod();
  }

  aboutToAppear(): void {
    this.updateTime();
    this.refreshCurrentPeriod();
    this.timer = setInterval(() => {
      this.updateTime();
    }, 1000);
  }

  @State currentPeriod: Period | null = null;

  private getCurrentPeriod(): Period | null {
    if (this.flowList.length === 0) return null;
    const now = this.currentTime;

    // 优先返回正在进行中的
    for (const p of this.flowList) {
      if (p.isOngoing(now)) return p;
    }
    // 返回最近即将开始的
    const future = this.flowList.filter(p => p.startTime > now);
    return future.length > 0 ? future[0] : null;
  }

  private refreshCurrentPeriod(): void {
    this.currentPeriod = this.getCurrentPeriod();
  }

  /** 获取后续事务列表（排除第一个） */
  private getUpcomingPeriods(): Period[] {
    const current = this.currentPeriod;
    if (!current) return this.flowList.slice(0, 10);
    return this.flowList.filter(p => p !== current).slice(0, 20);
  }

  /** 获取事务的颜色 */
  private getPeriodColor(period: Period): string {
    switch (period.type) {
      case PeriodType.TEST:
        return '#F48FB1';
      case PeriodType.CLASSES:
        return colorFromUid(period.fromUid || period.uid);
      default:
        return colorFromUid(period.fromUid || period.uid);
    }
  }

  /** 格式化日期范围文字 */
  private formatTimeRange(period: Period): string {
    const now = this.currentTime;
    const startStr = friendlyTime(period.startTime, now);
    const endH = period.endTime.getHours().toString().padStart(2, '0');
    const endM = period.endTime.getMinutes().toString().padStart(2, '0');
    return `${startStr} - ${endH}:${endM}`;
  }

  @Builder
  MainCard(period: Period) {
    Column({ space: 0 }) {
      Stack() {
        // 渐变背景层
        Column()
          .width('100%')
          .height('100%')
          .borderRadius(24)
          .position({ x: 0, y: 0 })

        // 卡片内容
        Column({ space: 16 }) {
          // 标题行
          Row({ space: 12 }) {
            ColorIndicator({
              color: this.getPeriodColor(period),
              type: period.type,
              indicatorSize: 16
            })
            Text(period.summary)
              .fontSize(20)
              .fontWeight(600) // SemiBold
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')

          // 地点行
          if (period.location.length > 0) {
            Row({ space: 8 }) {
              Image($r('sys.media.ohos_ic_public_location'))
                .width(14)
                .height(14)
                .fillColor($r('app.color.text_secondary'))
              Text(period.location)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }

          // 时间行
          Row({ space: 6 }) {
            Text('🕐')
              .fontSize(14)
            Text(this.formatTimeRange(period))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }

          // 倒计时
          Text(period.isOngoing(this.currentTime) ?
            `离结束还有 ${formatCountdown(period.countdownSeconds(this.currentTime))}` :
            `开始还有 ${formatCountdown(period.countdownSeconds(this.currentTime))}`
          )
            .fontSize(16)
            .fontColor(this.getPeriodColor(period))
            .fontWeight(600) // SemiBold

          // 进度条（仅进行中显示）
          if (period.isOngoing(this.currentTime)) {
            Column({ space: 6 }) {
              Row() {
                Blank()
                Text(`${Math.round(period.progress(this.currentTime) * 100)}%`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')

              Stack() {
                Row()
                  .width('100%')
                  .height(10)
                  .borderRadius(5)
                  .backgroundColor($r('app.color.progress_bg'))
                Row()
                  .width(`${period.progress(this.currentTime) * 100}%`)
                  .height(10)
                  .borderRadius(5)
                  .backgroundColor(this.getPeriodColor(period))
                  .animation({
                    duration: 1000,
                    curve: Curve.EaseOut
                  })
              }
              .width('100%')
            }
          }
        }
        .width('100%')
        .padding(22)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(24)
      .shadow({
        radius: 20,
        color: this.getPeriodColor(period) + '30',
        offsetX: 0,
        offsetY: 8
      })
      .clip(true)
    }
    .onClick(() => {
      if (period.type === PeriodType.CLASSES) {
        const param: CourseScheduleParam = { courseUid: period.fromUid };
        this.navStack.pushPathByName('CourseSchedule', param);
      }
    })
  }

  @Builder
  SmallCard(period: Period) {
    Row({ space: 14 }) {
      ColorIndicator({
        color: this.getPeriodColor(period),
        type: period.type,
        indicatorSize: 14
      })

      Column({ space: 6 }) {
        Text(period.summary)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Row({ space: 10 }) {
          Text(this.formatTimeRange(period))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          if (period.location.length > 0) {
            Text(period.location)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (period.isOngoing(this.currentTime)) {
        Column() {
          Text('进行中')
            .fontSize(11)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(12)
        .backgroundColor(this.getPeriodColor(period))
        .shadow({
          radius: 6,
          color: this.getPeriodColor(period) + '40',
          offsetX: 0,
          offsetY: 2
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(18)
    .shadow({
      radius: 8,
      color: '#10000000',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      if (period.type === PeriodType.CLASSES) {
        const param: CourseScheduleParam = { courseUid: period.fromUid };
        this.navStack.pushPathByName('CourseSchedule', param);
      }
    })
  }

  build() {
    Column() {
      // 标题栏 - 现代化设计
      Row() {
        Column({ space: 4 }) {
          Text('接下来')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.getDateString())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        // 当前时间显示 - 胶囊样式
        Column({ space: 2 }) {
          Text(this.formatCurrentTime())
            .fontSize(20)
            .fontWeight(600) // SemiBold
            .fontColor($r('app.color.color_blue'))
          Text('当前时间')
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
        }
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .borderRadius(14)
        .backgroundColor($r('app.color.color_blue') + '12')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topRectHeight + 10, bottom: 12 })

      // 内容列表
      if (this.flowList.length === 0) {
        EmptyView({
          icon: '🎉',
          title: '暂无安排',
          subtitle: '添加任务或登录后查看课程安排'
        })
      } else {
        Scroll() {
          Column({ space: 14 }) {
            // 主卡片
            if (this.currentPeriod !== null) {
              this.MainCard(this.currentPeriod)
            }

            // 后续事务
            if (this.getUpcomingPeriods().length > 0) {
              Column({ space: 10 }) {
                Text('接下来')
                  .fontSize(15)
                  .fontColor($r('app.color.text_secondary'))
                  .fontWeight(FontWeight.Medium)
                  .padding({ left: 4 })

                Column({ space: 10 }) {
                  ForEach(this.getUpcomingPeriods(), (period: Period) => {
                    this.SmallCard(period)
                  }, (period: Period) => period.uid)
                }
              }
            }

            // 底部留白（避免被悬浮导航栏遮挡）
            Blank().height(64 + this.bottomRectHeight + 20)
          }
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }

  private getDateString(): string {
    const now = this.currentTime;
    const months = ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'];
    return `${now.getFullYear()}年${months[now.getMonth()]}${now.getDate()}日`;
  }

  private formatCurrentTime(): string {
    const h = this.currentTime.getHours().toString().padStart(2, '0');
    const m = this.currentTime.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
  }
}

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(error));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  /** 从 AbilityContext.config 读取当前深色模式状态 */
  private syncDarkMode(): void {
    try {
      const isDark = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.setOrCreate('isDarkMode', isDark);
      // 同步更新窗口背景色和系统栏属性，实现颜色模式切换时同步变化
      if (this.mainWindow) {
        const bgColor = isDark ? '#000000' : '#F2F2F7'; // 与 app_background 一致
        const tabBarBgColor = isDark ? '#1C1C1E' : '#FFFFFF'; // 与 tab_bar_bg 一致
        this.mainWindow.setWindowBackgroundColor(bgColor);
        const navBarProps: window.SystemBarProperties = {
          navigationBarColor: tabBarBgColor,
          navigationBarContentColor: isDark ? '#FFFFFF' : '#000000',
          statusBarColor: bgColor,
          statusBarContentColor: isDark ? '#FFFFFF' : '#000000'
        };
        this.mainWindow.setWindowSystemBarProperties(navBarProps).catch(() => {
          // TODO: Implement error handling.
        });
      }
    } catch {}
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    try {
      const windowClass = windowStage.getMainWindowSync();
      this.mainWindow = windowClass;
      // 获取当前深色模式状态
      const isDark = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      const bgColor = isDark ? '#000000' : '#F2F2F7'; // 与 app_background 一致
      const tabBarBgColor = isDark ? '#1C1C1E' : '#FFFFFF'; // 与 tab_bar_bg 一致

      // 设置窗口背景色
      windowClass.setWindowBackgroundColor(bgColor);

      // 设置系统栏属性（状态栏和导航栏背景色）
      const navBarProps: window.SystemBarProperties = {
        statusBarColor: bgColor,
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
        navigationBarColor: tabBarBgColor,
        navigationBarContentColor: isDark ? '#FFFFFF' : '#000000'
      };
      windowClass.setWindowSystemBarProperties(navBarProps);

      // 显示系统状态栏（沉浸式），隐藏底部导航栏（由 App 自己绘制悬浮 TabBar）
      windowClass.setWindowSystemBarEnable(['status']);
      // 启用全屏延伸布局：内容延伸到状态栏区域，然后通过 padding 避开
      windowClass.setWindowLayoutFullScreen(true);

      // 读取状态栏高度，写入 AppStorage
      const density = display.getDefaultDisplaySync().densityPixels;
      const topAvoid = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.setOrCreate('topRectHeight', topAvoid.topRect.height / density);
      AppStorage.setOrCreate('bottomRectHeight', 0); // 底部导航栏已隐藏

      // 读取系统深浅色模式，同步到 AppStorage
      this.syncDarkMode();

      // 订阅安全区域变化（横竖屏切换、分屏等场景）
      windowClass.on('avoidAreaChange', (areaData) => {
        const d = display.getDefaultDisplaySync().densityPixels;
        const avoidArea: window.AvoidArea = areaData.area as window.AvoidArea;
        if (areaData.type === window.AvoidAreaType.TYPE_SYSTEM) {
          AppStorage.setOrCreate('topRectHeight', avoidArea.topRect.height / d);
        }
      });

      hilog.info(DOMAIN, 'testTag', 'Immersive mode set successfully, isDarkMode: %{public}s', isDark.toString());
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to set immersive mode. Cause: %{public}s', JSON.stringify(error));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    this.syncDarkMode();
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}

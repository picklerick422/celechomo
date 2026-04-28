// utils/ThemeUtil.ets - 外观模式切换工具
import { ConfigurationConstant } from '@kit.AbilityKit';
import common from '@ohos.app.ability.common';
import { ThemeMode } from '../pages/Index';

export function toColorMode(mode: ThemeMode): ConfigurationConstant.ColorMode {
  if (mode === 'light') return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  if (mode === 'dark') return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
}

export function applyThemeMode(context: common.UIAbilityContext, mode: ThemeMode): void {
  context.getApplicationContext().setColorMode(toColorMode(mode));
}

export function themeModeLabel(mode: ThemeMode): string {
  if (mode === 'light') return '浅色模式';
  if (mode === 'dark') return '深色模式';
  return '跟随系统';
}

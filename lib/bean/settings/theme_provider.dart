import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/constants.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  bool useDynamicColor = false;
  late ThemeData light;
  late ThemeData dark;

  /// 当前字体：自定义文件 > 内置 MI Sans > 系统
  String? currentFontFamily = customAppFontFamily;

  void refreshFontFamily() {
    final path = GStorage.getSetting(SettingsKeys.customFontPath) as String;
    if (path.isNotEmpty) {
      currentFontFamily = kCustomFontFamilyName;
    } else {
      currentFontFamily = GStorage.getSetting(SettingsKeys.useSystemFont)
          ? null
          : customAppFontFamily;
    }
  }

  /// Returns true if the effective theme is dark mode.
  /// Automatically gets platform brightness when themeMode is ThemeMode.system.
  bool isEffectiveDark() {
    if (themeMode == ThemeMode.dark) return true;
    if (themeMode == ThemeMode.light) return false;
    final platformBrightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return platformBrightness == Brightness.dark;
  }

  void setTheme(ThemeData light, ThemeData dark, {bool notify = true}) {
    this.light = light;
    this.dark = dark;
    if (notify) notifyListeners();
  }

  void setThemeMode(ThemeMode mode, {bool notify = true}) {
    themeMode = mode;
    if (notify) notifyListeners();
  }

  void setDynamic(bool useDynamicColor, {bool notify = true}) {
    this.useDynamicColor = useDynamicColor;
    if (notify) notifyListeners();
  }

  void setFontFamily(bool useSystemFont, {bool notify = true}) {
    refreshFontFamily();
    if (notify) notifyListeners();
  }
}

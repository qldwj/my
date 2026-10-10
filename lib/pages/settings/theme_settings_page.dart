import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/utils/constants.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/settings/settings_list.dart';
import 'package:yhdm/bean/settings/theme_provider.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/services/font_service.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/utils/device.dart';
import 'package:yhdm/utils/theme.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late dynamic defaultDanmakuArea;
  late dynamic defaultThemeColor;
  late bool oledEnhance;
  late bool useDynamicColor;
  late bool showWindowButton;
  late bool useSystemFont;
  late final ThemeProvider themeProvider;

  /// ⭐ 选择自定义字体文件并应用
  Future<void> _pickCustomFont() async {
    final error = await FontService.pickAndApply();
    if (!mounted) return;
    if (error != null) {
      KazumiDialog.showToast(message: '❌ $error');
      return;
    }
    themeProvider.setFontFamily(useSystemFont);
    setState(() {});
    KazumiDialog.showToast(message: AppLocalizations.of(context)!.setBFontChanged);
  }

  @override
  void initState() {
    super.initState();
    defaultThemeColor = GStorage.getSetting(SettingsKeys.themeColor);
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    useDynamicColor = GStorage.getSetting(SettingsKeys.useDynamicColor);
    showWindowButton = GStorage.getSetting(SettingsKeys.showWindowButton);
    useSystemFont = GStorage.getSetting(SettingsKeys.useSystemFont);
    themeProvider = context.read<ThemeProvider>();
  }

  void onBackPressed(BuildContext context) {
    if (KazumiDialog.observer.hasKazumiDialog) {
      KazumiDialog.dismiss();
      return;
    }
  }

  void setTheme(Color? color) {
    final seedColor = color ?? const Color(0xFFFF6FA5);
    var lightTheme = ThemeData(
      useMaterial3: true,
      fontFamily: themeProvider.currentFontFamily,
      brightness: Brightness.light,
      colorSchemeSeed: seedColor,
      progressIndicatorTheme: progressIndicatorTheme2024,
      sliderTheme: sliderTheme2024,
      pageTransitionsTheme: pageTransitionsTheme2024,
    );
    var defaultDarkTheme = ThemeData(
      useMaterial3: true,
      fontFamily: themeProvider.currentFontFamily,
      brightness: Brightness.dark,
      colorSchemeSeed: seedColor,
      progressIndicatorTheme: progressIndicatorTheme2024,
      sliderTheme: sliderTheme2024,
      pageTransitionsTheme: pageTransitionsTheme2024,
    );
    var oledTheme = oledDarkTheme(defaultDarkTheme);
    themeProvider.setTheme(
      lightTheme,
      oledEnhance ? oledTheme : defaultDarkTheme,
    );
    defaultThemeColor = seedColor.toARGB32().toRadixString(16);
    GStorage.putSetting(SettingsKeys.themeColor, defaultThemeColor);
  }

  void resetTheme() {
    // 默认配色 = 粉色；统一走 setTheme 存具体 ARGB，不再使用 'default' 特例
    setTheme(const Color(0xFFFF6FA5));
  }

  void updateOledEnhance() {
    dynamic color;
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    if (defaultThemeColor == 'default') {
      color = const Color(0xFFFF6FA5);
    } else {
      color = Color(int.parse(defaultThemeColor, radix: 16));
    }
    setTheme(color);
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: SysAppBar(title: Text(l10n.appearanceSettings)),
        body: SettingsList(
          maxWidth: 1000,
          sections: [
            SettingsSection(
              title: Text(l10n.themeAppearance,
                  style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.switchTile(
                  enabled: !Platform.isIOS,
                  onToggle: (value) async {
                    useDynamicColor = value ?? !useDynamicColor;
                    await GStorage.putSetting(
                        SettingsKeys.useDynamicColor, useDynamicColor);
                    themeProvider.setDynamic(useDynamicColor);
                    setState(() {});
                  },
                  title: Text(l10n.setBDynamicColor, style: TextStyle(fontFamily: fontFamily)),
                  initialValue: useDynamicColor,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    useSystemFont = value ?? !useSystemFont;
                    await GStorage.putSetting(
                        SettingsKeys.useSystemFont, useSystemFont);
                    themeProvider.setFontFamily(useSystemFont);
                    dynamic color;
                    if (defaultThemeColor == 'default') {
                      color = const Color(0xFFFF6FA5);
                    } else {
                      color = Color(int.parse(defaultThemeColor, radix: 16));
                    }
                    setTheme(color);
                    setState(() {});
                  },
                  title:
                      Text(l10n.setBUseSystemFont, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setBUseSystemFontDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: useSystemFont,
                ),
                SettingsTile(
                  onPressed: (_) => _pickCustomFont(),
                  title:
                      Text(l10n.setBCustomFont, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setBCustomFontDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
              bottomInfo: Text(l10n.setBDynamicColorNote,
                  style: TextStyle(fontFamily: fontFamily)),
            ),
            SettingsSection(
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    oledEnhance = value ?? !oledEnhance;
                    await GStorage.putSetting(
                        SettingsKeys.oledEnhance, oledEnhance);
                    updateOledEnhance();
                    setState(() {});
                  },
                  title:
                      Text(l10n.setBOledOptimize, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setBOledOptimizeDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: oledEnhance,
                ),
              ],
            ),
            if (isDesktop())
              SettingsSection(
                tiles: [
                  SettingsTile.switchTile(
                    onToggle: (value) async {
                      showWindowButton = value ?? !showWindowButton;
                      await GStorage.putSetting(
                          SettingsKeys.showWindowButton, showWindowButton);
                      setState(() {});
                    },
                    title: Text(l10n.setBSystemTitleBar,
                        style: TextStyle(fontFamily: fontFamily)),
                    description: Text(l10n.setBRestartToApply,
                        style: TextStyle(fontFamily: fontFamily)),
                    initialValue: showWindowButton,
                  ),
                ],
              ),
            if (Platform.isAndroid)
              SettingsSection(
                tiles: [
                  SettingsTile(
                    onPressed: (_) async {
                      context.pushNamed('/settings/theme/display');
                    },
                    title:
                        Text(l10n.setBRefreshRate, style: TextStyle(fontFamily: fontFamily)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

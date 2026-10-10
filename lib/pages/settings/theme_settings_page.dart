import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/card/palette_card.dart';
import 'package:yhdm/utils/constants.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/settings/settings_dropdown_tile.dart';
import 'package:yhdm/bean/settings/settings_list.dart';
import 'package:yhdm/bean/settings/theme_provider.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/settings/color_type.dart';
import 'package:yhdm/services/font_service.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yhdm/utils/device.dart';
import 'package:yhdm/utils/theme.dart';

/// Resolve a [colorThemeTypes] labelKey to its localized label.
String _colorLabel(String labelKey, AppLocalizations l10n) {
  switch (labelKey) {
    case 'setDColorPink':
      return l10n.setDColorPink;
    case 'setDColorDefault':
      return l10n.setDColorDefault;
    case 'setDColorTeal':
      return l10n.setDColorTeal;
    case 'setDColorBlue':
      return l10n.setDColorBlue;
    case 'setDColorIndigo':
      return l10n.setDColorIndigo;
    case 'setDColorViolet':
      return l10n.setDColorViolet;
    case 'setDColorYellow':
      return l10n.setDColorYellow;
    case 'setDColorOrange':
      return l10n.setDColorOrange;
    case 'setDColorDeepOrange':
      return l10n.setDColorDeepOrange;
    default:
      return labelKey;
  }
}

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late dynamic defaultDanmakuArea;
  late dynamic defaultThemeMode;
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
    defaultThemeMode = GStorage.getSetting(SettingsKeys.themeMode);
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
    final seedColor = color ?? const Color(0xffEC407A);
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
    // 默认配色 = 绿色；统一走 setTheme 存具体 ARGB，不再使用 'default' 特例
    setTheme(const Color(0xffEC407A));
  }

  void updateTheme(String theme) async {
    if (theme == 'dark') {
      themeProvider.setThemeMode(ThemeMode.dark);
    }
    if (theme == 'light') {
      themeProvider.setThemeMode(ThemeMode.light);
    }
    if (theme == 'system') {
      themeProvider.setThemeMode(ThemeMode.system);
    }
    await GStorage.putSetting(SettingsKeys.themeMode, theme);
    setState(() {
      defaultThemeMode = theme;
    });

    // Update Windows title bar theme
    if (Platform.isWindows) {
      await windowManager.setBrightness(
          themeProvider.isEffectiveDark() ? Brightness.dark : Brightness.light);
    }
  }

  void updateOledEnhance() {
    dynamic color;
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    if (defaultThemeColor == 'default') {
      color = const Color(0xffEC407A);
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
                SettingsDropdownTile<String>(
                  title: Text(l10n.setBDarkModeTitle,
                      style: TextStyle(fontFamily: fontFamily)),
                  value: defaultThemeMode,
                  fallbackLabel: l10n.languageFollowSystem,
                  options: {
                    'system': l10n.languageFollowSystem,
                    'light': l10n.lightMode,
                    'dark': l10n.darkMode,
                  },
                  icons: const {
                    'system': Icons.brightness_auto_rounded,
                    'light': Icons.light_mode_rounded,
                    'dark': Icons.dark_mode_rounded,
                  },
                  onChanged: updateTheme,
                ),
                SettingsTile(
                  enabled: !useDynamicColor,
                  onPressed: (_) async {
                    KazumiDialog.show(builder: (context) {
                      return AlertDialog(
                        title: Text(l10n.setBColorScheme,
                            style: TextStyle(fontFamily: fontFamily)),
                        content: StatefulBuilder(builder:
                            (BuildContext context, StateSetter setState) {
                          final List<Map<String, dynamic>> colorThemes =
                              colorThemeTypes;
                          return Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: isDesktop() ? 8 : 0,
                            children: [
                              ...colorThemes.map(
                                (e) {
                                  final index = colorThemes.indexOf(e);
                                  return GestureDetector(
                                    onTap: () {
                                      setTheme(e['color']);
                                      KazumiDialog.dismiss();
                                    },
                                    child: Column(
                                      children: [
                                        PaletteCard(
                                          color: e['color'],
                                          selected:
                                              (e['color'].toARGB32().toRadixString(16) ==
                                                      defaultThemeColor ||
                                                  (defaultThemeColor == 'default' &&
                                                      index == 0)),
                                        ),
                                        Text(_colorLabel(e['labelKey'], l10n)),
                                      ],
                                    ),
                                  );
                                },
                              )
                            ],
                          );
                        }),
                      );
                    });
                  },
                  title: Text(l10n.setBColorScheme, style: TextStyle(fontFamily: fontFamily)),
                ),
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
                      color = const Color(0xffEC407A);
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

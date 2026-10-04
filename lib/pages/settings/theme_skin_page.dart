import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/bean/widget/anime_theme_preview.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/theme.dart';

/// 番剧主题页（AnimeFlow 预览卡风格）
///
/// 顶部：深色 / 浅色 / 跟随系统 三张迷你预览卡，点击即切换外观模式（带动画）；
/// 下方：动漫主题配色色圆（选中动画）。
/// 返回层级：本页 → 设置页 → 我的页面。
class ThemeSkinPage extends StatefulWidget {
  const ThemeSkinPage({super.key});

  @override
  State<ThemeSkinPage> createState() => _ThemeSkinPageState();
}

class _AnimeSkin {
  final String id;
  final Color color;
  const _AnimeSkin(this.id, this.color);
}

const List<_AnimeSkin> _skins = [
  _AnimeSkin('default', Color(0xff4CAF50)),
  _AnimeSkin('sakura', Color(0xffEC407A)),
  _AnimeSkin('gate', Color(0xff2196F3)),
  _AnimeSkin('violet', Color(0xff6750a4)),
  _AnimeSkin('camp', Color(0xff4fc3f7)),
  _AnimeSkin('crimson', Color(0xffe53935)),
  _AnimeSkin('golden', Color(0xfffbc02d)),
  _AnimeSkin('mint', Color(0xff26a69a)),
  _AnimeSkin('mecha', Color(0xff607d8b)),
];

/// Localized theme display name, keyed by [_AnimeSkin.id].
String _skinName(String id, AppLocalizations l10n) {
  switch (id) {
    case 'default':
      return l10n.setDThemeDefault;
    case 'sakura':
      return l10n.setDThemeSakura;
    case 'gate':
      return l10n.setDThemeGate;
    case 'violet':
      return l10n.setDThemeViolet;
    case 'camp':
      return l10n.setDThemeCamp;
    case 'crimson':
      return l10n.setDThemeCrimson;
    case 'golden':
      return l10n.setDThemeGolden;
    case 'mint':
      return l10n.setDThemeMint;
    case 'mecha':
      return l10n.setDThemeMecha;
  }
}

/// Localized color nickname, keyed by [_AnimeSkin.id].
String _skinDesc(String id, AppLocalizations l10n) {
  switch (id) {
    case 'default':
      return l10n.setDThemeClassicGreen;
    case 'sakura':
      return l10n.setDThemeSakuraPink;
    case 'gate':
      return l10n.setDThemeTimeBlue;
    case 'violet':
      return l10n.setDThemeEternalPurple;
    case 'camp':
      return l10n.setDThemeSkyBlue;
    case 'crimson':
      return l10n.setDThemeBladeRed;
    case 'golden':
      return l10n.setDThemeAmberGold;
    case 'mint':
      return l10n.setDThemeMintGreen;
    case 'mecha':
      return l10n.setDThemeMechaSilver;
  }
}

class _ThemeSkinPageState extends State<ThemeSkinPage> {
  late String _currentColorHex;

  @override
  void initState() {
    super.initState();
    _currentColorHex =
        GStorage.getSetting(SettingsKeys.themeColor).toString();
  }

  String _hexOf(Color c) => c.toARGB32().toRadixString(16);

  bool _isColorSelected(_AnimeSkin skin) {
    if (_currentColorHex.isEmpty || _currentColorHex == 'default') {
      return skin.id == 'default';
    }
    return _hexOf(skin.color) == _currentColorHex;
  }

  void _setMode(ThemeMode mode) {
    GStorage.putSetting(SettingsKeys.themeMode, mode.name);
    context.read<ThemeProvider>().setThemeMode(mode);
    setState(() {});
  }

  void _applySkin(_AnimeSkin skin) {
    final tp = context.read<ThemeProvider>();
    final l10n = AppLocalizations.of(context)!;
    final light = ThemeData(
      useMaterial3: true,
      fontFamily: tp.currentFontFamily,
      brightness: Brightness.light,
      colorSchemeSeed: skin.color,
      progressIndicatorTheme: progressIndicatorTheme2024,
      sliderTheme: sliderTheme2024,
      pageTransitionsTheme: pageTransitionsTheme2024,
    );
    final dark = ThemeData(
      useMaterial3: true,
      fontFamily: tp.currentFontFamily,
      brightness: Brightness.dark,
      colorSchemeSeed: skin.color,
      progressIndicatorTheme: progressIndicatorTheme2024,
      sliderTheme: sliderTheme2024,
      pageTransitionsTheme: pageTransitionsTheme2024,
    );
    final oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    tp.setTheme(light, oledEnhance ? oledDarkTheme(dark) : dark);
    GStorage.putSetting(SettingsKeys.themeColor, _hexOf(skin.color));
    setState(() => _currentColorHex = _hexOf(skin.color));
    KazumiDialog.showToast(
      message: l10n.setDThemeSwitched(name: _skinName(skin.id, l10n)),
    );
  }

  Widget glassPanel({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding ?? const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.15),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tp = context.watch<ThemeProvider>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: SysAppBar(title: Text(l10n.themeSkinTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            l10n.themeAppearance,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _setMode(ThemeMode.dark),
                  child: ThemePreviewCard(
                    bg: const Color(0xFF020617),
                    primary: const Color(0xFF3B82F6),
                    icon: Icons.nightlight_round,
                    title: l10n.darkMode,
                    subtitle: '',
                    titleColor: Colors.white,
                    subtitleColor: const Color(0xFF6B7280),
                    selected: tp.themeMode == ThemeMode.dark,
                  ),
                ),
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: () => _setMode(ThemeMode.light),
                  child: ThemePreviewCard(
                    bg: const Color(0xFFF8FAFC),
                    primary: const Color(0xFFFACC15),
                    icon: Icons.wb_sunny,
                    title: l10n.lightMode,
                    subtitle: '',
                    titleColor: Colors.black,
                    subtitleColor: Colors.black54,
                    selected: tp.themeMode == ThemeMode.light,
                  ),
                ),
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: () => _setMode(ThemeMode.system),
                  child: ThemePreviewCard(
                    bg: const Color(0xFF020617),
                    primary: colors.primary,
                    icon: Icons.settings,
                    title: l10n.languageFollowSystem,
                    subtitle: '',
                    titleColor: Colors.white,
                    subtitleColor: Colors.white60,
                    overlay: const DiagonalOverlay(),
                    selected: tp.themeMode == ThemeMode.system,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.themeColorTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          glassPanel(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final skin in _skins)
                  GestureDetector(
                    onTap: () => _applySkin(skin),
                    child: Tooltip(
                      message: _skinDesc(skin.id, l10n),
                      child: SizedBox(
                        width: 64,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: skin.color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isColorSelected(skin)
                                      ? colors.primary
                                      : colors.outlineVariant
                                          .withValues(alpha: 0.5),
                                  width: _isColorSelected(skin) ? 2.5 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: skin.color.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: _isColorSelected(skin)
                                  ? Icon(
                                      Icons.check_rounded,
                                      size: 20,
                                      color:
                                          skin.color.computeLuminance() > 0.55
                                          ? Colors.black87
                                          : Colors.white,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _skinName(skin.id, l10n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

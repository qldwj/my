import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/theme.dart';

/// 番剧主题皮肤页
///
/// 提供多套以动漫命名的主题配色，点选即应用全局配色。
/// 返回层级：本页 → 设置页 → 我的页面（标准 pushNamed/pop，不直接跳回我的页）。
class ThemeSkinPage extends StatefulWidget {
  const ThemeSkinPage({super.key});

  @override
  State<ThemeSkinPage> createState() => _ThemeSkinPageState();
}

class _AnimeSkin {
  final String name;
  final String desc;
  final Color color;
  const _AnimeSkin(this.name, this.desc, this.color);
}

const List<_AnimeSkin> _skins = [
  _AnimeSkin('默认配色', '经典绿', Color(0xff4CAF50)),
  _AnimeSkin('次元城·樱', '樱花粉', Color(0xffEC407A)),
  _AnimeSkin('命运·门', '时间蓝', Color(0xff2196F3)),
  _AnimeSkin('紫罗兰永恒', '永恒紫', Color(0xff6750a4)),
  _AnimeSkin('露营·晴空', '晴空蓝', Color(0xff4fc3f7)),
  _AnimeSkin('绯红·刀', '刀红', Color(0xffe53935)),
  _AnimeSkin('金瞳', '琥珀金', Color(0xfffbc02d)),
  _AnimeSkin('薄荷·凪', '薄荷青', Color(0xff26a69a)),
  _AnimeSkin('黑银·机械', '机械银', Color(0xff607d8b)),
];

class _ThemeSkinPageState extends State<ThemeSkinPage> {
  late String _currentColorHex;

  @override
  void initState() {
    super.initState();
    _currentColorHex =
        GStorage.getSetting(SettingsKeys.themeColor).toString();
  }

  String _hexOf(Color c) => c.toARGB32().toRadixString(16);

  bool _isSelected(_AnimeSkin skin) {
    if (_currentColorHex.isEmpty || _currentColorHex == 'default') {
      return skin.name == '默认配色';
    }
    return _hexOf(skin.color) == _currentColorHex;
  }

  void _applySkin(_AnimeSkin skin) {
    final tp = context.read<ThemeProvider>();
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
    KazumiDialog.showToast(message: '已切换主题：${skin.name}');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(title: const Text('番剧主题')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '选择一套以动漫命名的主题配色，立即应用全局主题',
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.82,
            children: [
              for (final skin in _skins)
                _SkinCard(
                  skin: skin,
                  selected: _isSelected(skin),
                  onTap: () => _applySkin(skin),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkinCard extends StatelessWidget {
  const _SkinCard({
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  final _AnimeSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: skin.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: skin.color.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 24)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              skin.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? colors.primary : colors.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              skin.desc,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/settings_section_card.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 规则设置页
///
/// - 自动选择视频源（从播放设置迁入）
/// - 星标规则：标星的规则播放时无条件排最前（同步服务器）
/// - 选源排序模式：速度 / 清晰度 / 集数最多 / 自定义组合
class RuleSettingsPage extends StatefulWidget {
  const RuleSettingsPage({super.key});

  @override
  State<RuleSettingsPage> createState() => _RuleSettingsPageState();
}

class _RuleSettingsPageState extends State<RuleSettingsPage> {
  final PluginsController pluginsController = inject<PluginsController>();
  bool _autoSelectSource = false;
  Set<String> _starred = {};
  bool _loadingStar = true;

  // 排序模式
  bool _sortBySpeed = false;
  bool _sortByQuality = false;
  bool _sortByEpisodes = false;
  bool _useDefaultSort = true;

  @override
  void initState() {
    super.initState();
    _autoSelectSource = GStorage.getSetting(SettingsKeys.autoSelectSource);
    _loadSortPrefs();
    _loadStars();
  }

  void _loadSortPrefs() {
    _useDefaultSort = GStorage.getSetting(SettingsKeys.ruleSortDefault);
    _sortBySpeed = GStorage.getSetting(SettingsKeys.ruleSortSpeed);
    _sortByQuality = GStorage.getSetting(SettingsKeys.ruleSortQuality);
    _sortByEpisodes = GStorage.getSetting(SettingsKeys.ruleSortEpisodes);
  }

  Future<void> _saveSortPrefs() async {
    await GStorage.putSetting(SettingsKeys.ruleSortDefault, _useDefaultSort);
    await GStorage.putSetting(SettingsKeys.ruleSortSpeed, _sortBySpeed);
    await GStorage.putSetting(SettingsKeys.ruleSortQuality, _sortByQuality);
    await GStorage.putSetting(SettingsKeys.ruleSortEpisodes, _sortByEpisodes);
  }

  Future<void> _loadStars() async {
    final stars = await SocialService.getStarRules();
    if (!mounted) return;
    setState(() {
      _starred = stars.toSet();
      _loadingStar = false;
    });
  }

  Future<void> _toggleStar(String name) async {
    setState(() {
      if (_starred.contains(name)) {
        _starred.remove(name);
      } else {
        _starred.add(name);
      }
    });
    // 保存到服务器 + 本地
    final error =
        await SocialService.saveStarRules(_starred.toList());
    if (error != null && mounted) {
      KazumiDialog.showToast(message: '❌ 星标同步失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final plugins = pluginsController.pluginList.toList()
      ..sort((a, b) {
        final sa = _starred.contains(a.name) ? 0 : 1;
        final sb = _starred.contains(b.name) ? 0 : 1;
        if (sa != sb) return sa.compareTo(sb);
        return a.name.compareTo(b.name);
      });
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('规则设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsSectionCard(
            title: '播放',
            children: [
              SwitchListTile(
                title: const Text('自动选择视频源'),
                subtitle: const Text('开始观看时自动用第一个可用源播放'),
                value: _autoSelectSource,
                onChanged: (value) async {
                  setState(() => _autoSelectSource = value);
                  await GStorage.putSetting(
                      SettingsKeys.autoSelectSource, value);
                },
              ),
            ],
          ),
          SettingsSectionCard(
            title: '星标规则（播放时无条件排最前）',
            children: [
              if (_loadingStar)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (plugins.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('暂无规则'),
                )
              else
                for (final p in plugins)
                  SwitchListTile(
                    dense: true,
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    secondary: Icon(
                      _starred.contains(p.name)
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: _starred.contains(p.name)
                          ? Colors.amber
                          : colorScheme.outline,
                    ),
                    value: _starred.contains(p.name),
                    onChanged: (_) => _toggleStar(p.name),
                  ),
            ],
          ),
          SettingsSectionCard(
            title: '选源排序（可多选组合，未选则按默认速度）',
            children: [
              SwitchListTile(
                title: const Text('默认（按响应速度）'),
                value: _useDefaultSort,
                onChanged: (value) async {
                  setState(() => _useDefaultSort = value);
                  await _saveSortPrefs();
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('清晰度最高'),
                value: _sortByQuality,
                onChanged: (value) async {
                  setState(() => _sortByQuality = value);
                  await _saveSortPrefs();
                },
              ),
              SwitchListTile(
                title: const Text('集数最多'),
                value: _sortByEpisodes,
                onChanged: (value) async {
                  setState(() => _sortByEpisodes = value);
                  await _saveSortPrefs();
                },
              ),
              SwitchListTile(
                title: const Text('速度最快'),
                value: _sortBySpeed,
                onChanged: (value) async {
                  setState(() => _sortBySpeed = value);
                  await _saveSortPrefs();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

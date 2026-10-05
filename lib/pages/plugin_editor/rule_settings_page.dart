import 'package:yhdm/bean/widget/loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/widget/settings_section_card.dart';
import 'package:yhdm/bean/widget/source_rating_widget.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/plugins/plugins_controller.dart';
import 'package:yhdm/services/plugin/plugin_cookie_manager.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/sync/webdav.dart';

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
    // 本地星标为即时权威
    final stars = GStorage.getStringListSettingByName('starRules').toSet();
    // 配置了 WebDAV 时尝试从云端拉取并合并（跨设备保留两边标星）
    if (GStorage.getSetting(SettingsKeys.webDavURL).toString().isNotEmpty) {
      try {
        final webDav = WebDav();
        await webDav.init();
        final remote = await webDav.downloadStarRules();
        if (remote != null && remote.isNotEmpty) {
          stars.addAll(remote);
          await GStorage.putStringListSettingByName(
              'starRules', stars.toList());
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _starred = stars;
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
    // 保存到本地（即时权威）
    final list = _starred.toList();
    await GStorage.putStringListSettingByName('starRules', list);
    // 配置了 WebDAV 时同步上传到云端
    if (GStorage.getSetting(SettingsKeys.webDavURL).toString().isNotEmpty) {
      try {
        final webDav = WebDav();
        await webDav.init();
        await webDav.uploadStarRules(list);
      } catch (e) {
        if (mounted) {
          KazumiDialog.showToast(
              message: AppLocalizations.of(context)!
                  .setFWebdavSyncFail(error: e.toString()));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
        title: Text(l10n.setFRuleSettings),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsSectionCard(
            title: l10n.setFPlayback,
            children: [
              SwitchListTile(
                title: Text(l10n.setFAutoSelectSource),
                subtitle: Text(l10n.setFAutoSelectSourceSub),
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
            title: l10n.setFStarredRules,
            children: [
              if (_loadingStar)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: LoadingIndicator()),
                )
              else if (plugins.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.setFNoRules),
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
            title: l10n.setFSourceStabilityRating,
            children: [
              if (plugins.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.setFNoRules),
                )
              else
                for (final p in plugins)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(p.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: SourceRatingWidget(sourceId: p.name),
                  ),
            ],
          ),
          SettingsSectionCard(
            title: l10n.setFSourceSorting,
            children: [
              SwitchListTile(
                title: Text(l10n.setFDefaultSort),
                value: _useDefaultSort,
                onChanged: (value) async {
                  setState(() => _useDefaultSort = value);
                  await _saveSortPrefs();
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: Text(l10n.setFHighestQuality),
                value: _sortByQuality,
                onChanged: (value) async {
                  setState(() => _sortByQuality = value);
                  await _saveSortPrefs();
                },
              ),
              SwitchListTile(
                title: Text(l10n.setFMostEpisodes),
                value: _sortByEpisodes,
                onChanged: (value) async {
                  setState(() => _sortByEpisodes = value);
                  await _saveSortPrefs();
                },
              ),
              SwitchListTile(
                title: Text(l10n.setFFastestSpeed),
                value: _sortBySpeed,
                onChanged: (value) async {
                  setState(() => _sortBySpeed = value);
                  await _saveSortPrefs();
                },
              ),
            ],
          ),
          SettingsSectionCard(
            title: l10n.setFLoginCookie,
            children: [
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(l10n.setFCookieTtlDays),
                subtitle: Text(l10n.setFCookieTtlDaysSub),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _changeTtl(-1),
                    ),
                    Text(l10n.setFDays(count: PluginCookieManager.cookieTtlDays),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => _changeTtl(1),
                    ),
                  ],
                ),
              ),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(l10n.setFClearAllLoginState),
                subtitle: Text(l10n.setFClearAllLoginStateSub),
                trailing: TextButton(
                  onPressed: _clearAllCookies,
                  child: Text(l10n.setFClearAll),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeTtl(int delta) async {
    final cur = PluginCookieManager.cookieTtlDays;
    final next = (cur + delta).clamp(1, 365);
    await PluginCookieManager.setCookieTtlDays(next);
    if (mounted) setState(() {});
  }

  Future<void> _clearAllCookies() async {
    final confirmed = await KazumiDialog.show<bool>(
      builder: (context) {
        final dl10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(dl10n.setFClearAllLoginStateTitle),
          content: Text(dl10n.setFClearAllConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(dl10n.setFClear),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await PluginCookieManager.instance.clearAll();
    if (mounted) setState(() {});
    KazumiDialog.showToast(
        message: AppLocalizations.of(context)!.setFClearAllDone);
  }
}

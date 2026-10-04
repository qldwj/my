import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/network/image_acceleration.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// 镜像代理设置页面
class ApiProxyPage extends StatefulWidget {
  const ApiProxyPage({super.key});

  @override
  State<ApiProxyPage> createState() => _ApiProxyPageState();
}

class _ApiProxyPageState extends State<ApiProxyPage> {
  late TextEditingController _domainController;
  late bool _proxyEnabled;
  late Map<String, TextEditingController> _pathControllers;

  // 预设域名选项
  static const List<String> _presetDomains = [
    'https://api.qlyyz.top',
    'https://api.kazumi.fyi',
  ];

  // 原始端点 → 默认镜像路径
  static const Map<String, _ApiEndpoint> _endpoints = {
    'calendar': _ApiEndpoint(
      labelKey: 'setDEndpointCalendar',
      original: 'next.bgm.tv/p1/calendar',
      defaultMirrorPath: '/kazumi/v1/calendar',
    ),
    'trending': _ApiEndpoint(
      labelKey: 'setDEndpointTrending',
      original: 'next.bgm.tv/p1/trending/subjects',
      defaultMirrorPath: '/kazumi/v1/trending/subjects',
    ),
    'popular': _ApiEndpoint(
      labelKey: 'setDEndpointPopular',
      original: 'next.bgm.tv/p1/trending/subjects',
      defaultMirrorPath: '/kazumi/v1/popular/subjects',
    ),
    'season': _ApiEndpoint(
      labelKey: 'setDEndpointSeason',
      original: 'api.qlyyz.top/kazumi/v1/calendar/season',
      defaultMirrorPath: '/kazumi/v1/calendar/season',
    ),
    'search': _ApiEndpoint(
      labelKey: 'setDEndpointSearch',
      original: 'api.bgm.tv/v0/search/subjects',
      defaultMirrorPath: '/v0/search/subjects',
    ),
    'subject': _ApiEndpoint(
      labelKey: 'setDEndpointSubject',
      original: 'api.bgm.tv/v0/subjects/{id}',
      defaultMirrorPath: '/v0/subjects/{id}',
    ),
    'episodes': _ApiEndpoint(
      labelKey: 'setDEndpointEpisodes',
      original: 'api.bgm.tv/v0/episodes',
      defaultMirrorPath: '/v0/episodes',
    ),
    'characters': _ApiEndpoint(
      labelKey: 'setDEndpointCharacters',
      original: 'api.bgm.tv/v0/subjects/{id}/characters',
      defaultMirrorPath: '/v0/subjects/{id}/characters',
    ),
    'comments': _ApiEndpoint(
      labelKey: 'setDEndpointSubjectComments',
      original: 'next.bgm.tv/p1/subjects/{id}/comments',
      defaultMirrorPath: '/p1/subjects/{id}/comments',
    ),
    'episode_comments': _ApiEndpoint(
      labelKey: 'setDEndpointEpisodeComments',
      original: 'next.bgm.tv/p1/episodes/{id}/comments',
      defaultMirrorPath: '/p1/episodes/{id}/comments',
    ),
    'character_info': _ApiEndpoint(
      labelKey: 'setDEndpointCharacterInfo',
      original: 'next.bgm.tv/p1/characters/{id}',
      defaultMirrorPath: '/p1/characters/{id}',
    ),
    'character_comments': _ApiEndpoint(
      labelKey: 'setDEndpointCharacterComments',
      original: 'next.bgm.tv/p1/characters/{id}/comments',
      defaultMirrorPath: '/p1/characters/{id}/comments',
    ),
    'staff': _ApiEndpoint(
      labelKey: 'setDEndpointStaff',
      original: 'next.bgm.tv/p1/subjects/{id}/staffs/persons',
      defaultMirrorPath: '/p1/subjects/{id}/staffs/persons',
    ),
    'related': _ApiEndpoint(
      labelKey: 'setDEndpointRelated',
      original: 'api.bgm.tv/v0/subjects/{id}/subjects',
      defaultMirrorPath: '/v0/subjects/{id}/subjects',
    ),
  };

  /// Resolve an endpoint labelKey to its localized label.
  String _endpointLabel(String labelKey, AppLocalizations l10n) {
    switch (labelKey) {
      case 'setDEndpointCalendar':
        return l10n.setDEndpointCalendar;
      case 'setDEndpointTrending':
        return l10n.setDEndpointTrending;
      case 'setDEndpointPopular':
        return l10n.setDEndpointPopular;
      case 'setDEndpointSeason':
        return l10n.setDEndpointSeason;
      case 'setDEndpointSearch':
        return l10n.setDEndpointSearch;
      case 'setDEndpointSubject':
        return l10n.setDEndpointSubject;
      case 'setDEndpointEpisodes':
        return l10n.setDEndpointEpisodes;
      case 'setDEndpointCharacters':
        return l10n.setDEndpointCharacters;
      case 'setDEndpointSubjectComments':
        return l10n.setDEndpointSubjectComments;
      case 'setDEndpointEpisodeComments':
        return l10n.setDEndpointEpisodeComments;
      case 'setDEndpointCharacterInfo':
        return l10n.setDEndpointCharacterInfo;
      case 'setDEndpointCharacterComments':
        return l10n.setDEndpointCharacterComments;
      case 'setDEndpointStaff':
        return l10n.setDEndpointStaff;
      case 'setDEndpointRelated':
        return l10n.setDEndpointRelated;
      default:
        return labelKey;
    }
  }

  @override
  void initState() {
    super.initState();
    _domainController = TextEditingController(
      text: GStorage.getSetting(SettingsKeys.bangumiProxyDomain),
    );
    _proxyEnabled = GStorage.getSetting(SettingsKeys.enableBangumiProxy);
    _pathControllers = {};
    for (final entry in _endpoints.entries) {
      final saved = GStorage.getSetting(
        SettingsKeys.bangumiProxyPath(entry.key),
      );
      _pathControllers[entry.key] = TextEditingController(
        text: saved.isNotEmpty ? saved : entry.value.defaultMirrorPath,
      );
    }
  }

  @override
  void dispose() {
    _domainController.dispose();
    for (final c in _pathControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 自动补全 https://
  String _normalizeDomain(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  Future<void> _save() async {
    final domain = _normalizeDomain(_domainController.text);
    _domainController.text = domain;
    await GStorage.putSetting(SettingsKeys.bangumiProxyDomain, domain);
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, _proxyEnabled);
    for (final entry in _pathControllers.entries) {
      await GStorage.putSetting(
        SettingsKeys.bangumiProxyPath(entry.key),
        entry.value.text.trim(),
      );
    }
    ProxyManager.applyProxy();
    if (mounted) {
      KazumiDialog.showToast(message: AppLocalizations.of(context)!.setCSaved);
    }
  }

  Future<void> _testConnection() async {
    final domain = _normalizeDomain(_domainController.text);
    _domainController.text = domain;
    if (domain.isEmpty) {
      KazumiDialog.showToast(message: AppLocalizations.of(context)!.setCEnterMirrorDomainFirst);
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    KazumiDialog.showToast(message: l10n.setCTestingConnection);
    try {
      // 测试首页播放推送接口
      final url = '$domain/kazumi/v1/popular/subjects?limit=1';
      final uri = Uri.parse(url);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 10));
      client.close();
      if (response.statusCode == 200) {
        KazumiDialog.showToast(message: l10n.setCConnectionTestPassed);
      } else {
        KazumiDialog.showToast(message: l10n.setCConnectionFailed(statusCode: response.statusCode));
      }
    } catch (e) {
      KazumiDialog.showToast(message: l10n.setCConnectionTestFailed(error: e.toString()));
    }
  }

  /// 🆕 图片加速模式选择（直连 / ECH / 镜像）
  Future<void> _selectImageAcceleration() async {
    final l10n = AppLocalizations.of(context)!;
    final current = ImageAcceleration.fromSetting(
      GStorage.getSetting(SettingsKeys.imageAcceleration),
    );
    final selected = await KazumiDialog.show<ImageAcceleration>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.setCImageAcceleration),
        children: [
          RadioGroup<ImageAcceleration>(
            groupValue: current,
            onChanged: (value) => Navigator.of(ctx).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in ImageAcceleration.values)
                  RadioListTile<ImageAcceleration>(
                    value: mode,
                    title: Text(mode.label(l10n)),
                    subtitle: Text(mode.description(l10n)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (mounted && selected != null && selected != current) {
      await GStorage.putSetting(SettingsKeys.imageAcceleration, selected.name);
      ProxyManager.applyProxy();
      setState(() {});
    }
  }

  void _showDomainPicker() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
sheetAnimationStyle: kSheetAnimationStyle,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.setCChoosePresetDomain, style: Theme.of(ctx).textTheme.titleMedium),
              ),
              ..._presetDomains.map((domain) => ListTile(
                leading: Icon(Icons.language, color: cs.primary),
                title: Text(domain),
                subtitle: Text(
                  domain == 'https://api.kazumi.fyi' ? l10n.setCKazumiOfficialMirror : l10n.setCQlyyzMirror,
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _domainController.text = domain);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SysAppBar(title: Text(l10n.mirrorProxy)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 主域名设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dns_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(l10n.setCMirrorSettings, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(l10n.setCEnableApiMirror),
                    subtitle: Text(l10n.setCEnableApiMirrorDesc),
                    value: _proxyEnabled,
                    onChanged: (v) => setState(() => _proxyEnabled = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: Text(l10n.setCBangumiMirror),
                    subtitle: Text(l10n.setCBangumiMirrorDesc),
                    value: GStorage.getSetting(SettingsKeys.enableBangumiProxy),
                    onChanged: (v) {
                      GStorage.putSetting(SettingsKeys.enableBangumiProxy, v);
                      setState(() {});
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: Text(l10n.setCRuleRepoMirror),
                    subtitle: Text(l10n.setCRuleRepoMirrorDesc),
                    value: GStorage.getSetting(SettingsKeys.enableGitProxy),
                    onChanged: (v) {
                      GStorage.putSetting(SettingsKeys.enableGitProxy, v);
                      setState(() {});
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(),
                  // 🆕 图片加速（直连 / ECH / 镜像 三选一）
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.image_rounded),
                    title: Text(l10n.setCImageAcceleration),
                    subtitle: Text(l10n.setCImageAccelerationDesc),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ImageAcceleration.fromSetting(
                            GStorage.getSetting(SettingsKeys.imageAcceleration),
                          ).label(l10n),
                          style: TextStyle(color: cs.primary),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    onTap: () => _selectImageAcceleration(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _domainController,
                          decoration: InputDecoration(
                            labelText: l10n.setCMirrorMainDomain,
                            hintText: 'api.qlyyz.top',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.language),
                          ),
                          onSubmitted: (_) => _save(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _showDomainPicker,
                        icon: const Icon(Icons.arrow_drop_down_circle),
                        tooltip: l10n.setCChoosePresetDomain,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.setCDomainHint,
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 端点列表
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.api_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(l10n.setCEndpointPaths, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.setCEndpointPathsDesc,
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 每个端点
          ..._endpoints.entries.map((entry) => _buildEndpointCard(entry.key, entry.value)),

          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            onPressed: _testConnection,
            heroTag: 'test',
            icon: const Icon(Icons.wifi_find),
            label: Text(l10n.setCTest),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            onPressed: _save,
            heroTag: 'save',
            icon: const Icon(Icons.save),
            label: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointCard(String key, _ApiEndpoint endpoint) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _endpointLabel(endpoint.labelKey, l10n),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                final url = 'https://${endpoint.original}';
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              child: Text(
                l10n.setCOriginal(original: endpoint.original),
                style: TextStyle(fontSize: 11, color: cs.outline, decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pathControllers[key],
              decoration: InputDecoration(
                labelText: l10n.setCMirrorPath,
                hintText: endpoint.defaultMirrorPath,
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(Icons.route, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiEndpoint {
  final String labelKey;
  final String original;
  final String defaultMirrorPath;

  const _ApiEndpoint({
    required this.labelKey,
    required this.original,
    required this.defaultMirrorPath,
  });
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/network/image_acceleration.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
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
      label: '每日放送',
      original: 'next.bgm.tv/p1/calendar',
      defaultMirrorPath: '/kazumi/v1/calendar',
    ),
    'trending': _ApiEndpoint(
      label: '番剧趋势',
      original: 'next.bgm.tv/p1/trending/subjects',
      defaultMirrorPath: '/kazumi/v1/trending/subjects',
    ),
    'popular': _ApiEndpoint(
      label: '热门番剧',
      original: 'next.bgm.tv/p1/trending/subjects',
      defaultMirrorPath: '/kazumi/v1/popular/subjects',
    ),
    'season': _ApiEndpoint(
      label: '季节时间表',
      original: 'api.qlyyz.top/kazumi/v1/calendar/season',
      defaultMirrorPath: '/kazumi/v1/calendar/season',
    ),
    'search': _ApiEndpoint(
      label: '番剧搜索',
      original: 'api.bgm.tv/v0/search/subjects',
      defaultMirrorPath: '/v0/search/subjects',
    ),
    'subject': _ApiEndpoint(
      label: '番剧详情',
      original: 'api.bgm.tv/v0/subjects/{id}',
      defaultMirrorPath: '/v0/subjects/{id}',
    ),
    'episodes': _ApiEndpoint(
      label: '剧集列表',
      original: 'api.bgm.tv/v0/episodes',
      defaultMirrorPath: '/v0/episodes',
    ),
    'characters': _ApiEndpoint(
      label: '角色列表',
      original: 'api.bgm.tv/v0/subjects/{id}/characters',
      defaultMirrorPath: '/v0/subjects/{id}/characters',
    ),
    'comments': _ApiEndpoint(
      label: '条目评论',
      original: 'next.bgm.tv/p1/subjects/{id}/comments',
      defaultMirrorPath: '/p1/subjects/{id}/comments',
    ),
    'episode_comments': _ApiEndpoint(
      label: '剧集评论',
      original: 'next.bgm.tv/p1/episodes/{id}/comments',
      defaultMirrorPath: '/p1/episodes/{id}/comments',
    ),
    'character_info': _ApiEndpoint(
      label: '角色详情',
      original: 'next.bgm.tv/p1/characters/{id}',
      defaultMirrorPath: '/p1/characters/{id}',
    ),
    'character_comments': _ApiEndpoint(
      label: '角色评论',
      original: 'next.bgm.tv/p1/characters/{id}/comments',
      defaultMirrorPath: '/p1/characters/{id}/comments',
    ),
    'staff': _ApiEndpoint(
      label: '制作人员',
      original: 'next.bgm.tv/p1/subjects/{id}/staffs/persons',
      defaultMirrorPath: '/p1/subjects/{id}/staffs/persons',
    ),
    'related': _ApiEndpoint(
      label: '关联条目',
      original: 'api.bgm.tv/v0/subjects/{id}/subjects',
      defaultMirrorPath: '/v0/subjects/{id}/subjects',
    ),
  };

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
      KazumiDialog.showToast(message: '已保存');
    }
  }

  Future<void> _testConnection() async {
    final domain = _normalizeDomain(_domainController.text);
    _domainController.text = domain;
    if (domain.isEmpty) {
      KazumiDialog.showToast(message: '请先填写镜像域名');
      return;
    }
    KazumiDialog.showToast(message: '正在测试连接...');
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
        KazumiDialog.showToast(message: '✅ 连接测试通过');
      } else {
        KazumiDialog.showToast(message: '连接失败: ${response.statusCode}');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '连接测试失败: $e');
    }
  }

  /// 🆕 图片加速模式选择（直连 / ECH / 镜像）
  Future<void> _selectImageAcceleration() async {
    final current = ImageAcceleration.fromSetting(
      GStorage.getSetting(SettingsKeys.imageAcceleration),
    );
    final selected = await KazumiDialog.show<ImageAcceleration>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('图片加速'),
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
                    title: Text(mode.label),
                    subtitle: Text(mode.description),
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
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('选择预设域名', style: Theme.of(ctx).textTheme.titleMedium),
              ),
              ..._presetDomains.map((domain) => ListTile(
                leading: Icon(Icons.language, color: cs.primary),
                title: Text(domain),
                subtitle: Text(
                  domain == 'https://api.kazumi.fyi' ? 'Kazumi 官方镜像' : 'Qlyyz 镜像',
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
    return Scaffold(
      appBar: const SysAppBar(title: Text('镜像代理')),
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
                      const Text('镜像设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('启用 API 镜像代理'),
                    subtitle: const Text('开启后将通过自定义镜像域名请求数据'),
                    value: _proxyEnabled,
                    onChanged: (v) => setState(() => _proxyEnabled = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Bangumi 镜像'),
                    subtitle: const Text('同步Bangumi时使用镜像'),
                    value: GStorage.getSetting(SettingsKeys.enableBangumiProxy),
                    onChanged: (v) {
                      GStorage.putSetting(SettingsKeys.enableBangumiProxy, v);
                      setState(() {});
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('规则仓库镜像'),
                    subtitle: const Text('获取规则列表时使用镜像'),
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
                    title: const Text('图片加速'),
                    subtitle: const Text('加速 Bangumi 封面与头像加载'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ImageAcceleration.fromSetting(
                            GStorage.getSetting(SettingsKeys.imageAcceleration),
                          ).label,
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
                          decoration: const InputDecoration(
                            labelText: '镜像主域名',
                            hintText: 'api.qlyyz.top',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.language),
                          ),
                          onSubmitted: (_) => _save(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _showDomainPicker,
                        icon: const Icon(Icons.arrow_drop_down_circle),
                        tooltip: '选择预设域名',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '填写后所有 API 请求将通过此域名代理（自动补全 https://）',
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
                      const Text('端点路径配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '每个端点的原始地址和自定义镜像路径',
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
            label: const Text('测试'),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            onPressed: _save,
            heroTag: 'save',
            icon: const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointCard(String key, _ApiEndpoint endpoint) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              endpoint.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                final url = 'https://${endpoint.original}';
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              child: Text(
                '原始: ${endpoint.original}',
                style: TextStyle(fontSize: 11, color: cs.outline, decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pathControllers[key],
              decoration: InputDecoration(
                labelText: '镜像路径',
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
  final String label;
  final String original;
  final String defaultMirrorPath;

  const _ApiEndpoint({
    required this.label,
    required this.original,
    required this.defaultMirrorPath,
  });
}

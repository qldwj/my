import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/animeko_converter.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/encoding.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// 合集详情页面
///
/// 展示一个合集（Animeko Collection）中包含的所有动漫来源规则。
class CollectionDetailPage extends StatefulWidget {
  const CollectionDetailPage({super.key, required this.plugin});

  final Plugin plugin;

  @override
  State<CollectionDetailPage> createState() => _CollectionDetailPageState();
}

class _CollectionDetailPageState extends State<CollectionDetailPage> {
  late Plugin _plugin;
  bool _updating = false;
  bool _allEnabled = true;

  @override
  void initState() {
    super.initState();
    _plugin = widget.plugin;
  }

  /// 手动刷新合集
  Future<void> _refreshCollection() async {
    if (_updating || _plugin.collectionUrl.isEmpty) return;
    setState(() => _updating = true);

    try {
      final json = await PluginSiteClient.instance.requestText(
        _plugin.collectionUrl,
        method: 'GET',
      );
      if (json.trim().isEmpty) {
        KazumiDialog.showToast(message: '合集地址返回空');
        return;
      }

      final plugins = AnimekoRuleConverter.convertFromJson(json);
      if (plugins.isEmpty) {
        KazumiDialog.showToast(message: '未解析到规则');
        return;
      }

      // 去重
      final existingNames = _plugin.childPlugins.map((p) => p.name).toSet();
      int added = 0, updated = 0;
      for (final p in plugins) {
        bool found = false;
        for (int i = 0; i < _plugin.childPlugins.length; i++) {
          if (_plugin.childPlugins[i].name == p.name) {
            _plugin.childPlugins[i] = p;
            found = true;
            updated++;
            break;
          }
        }
        if (!found) {
          _plugin.childPlugins.add(p);
          added++;
        }
      }

      final now = DateTime.now();
      _plugin.collectionLastUpdate = _formatTime(now);
      // 从设置读取更新间隔
      final intervalMinutes = _getUpdateInterval();
      _plugin.collectionNextUpdate = _formatTime(now.add(Duration(minutes: intervalMinutes)));

      // 保存
      final ctrl = inject<PluginsController>();
      await ctrl.savePlugins();

      if (mounted) {
        setState(() {});
        KazumiDialog.showToast(
          message: added > 0
              ? '更新完成 +$added 新增, $updated 更新'
              : '更新完成 $updated 条已更新',
        );
      }
    } catch (e, st) {
      KazumiLogger().e('合集刷新失败', error: e, stackTrace: st);
      if (mounted) {
        KazumiDialog.showToast(message: '刷新失败: $e');
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  int _getUpdateInterval() {
    // 简单实现：从插件更新时间推算
    try {
      if (_plugin.collectionLastUpdate.isNotEmpty &&
          _plugin.collectionNextUpdate.isNotEmpty) {
        final last = DateTime.parse(_plugin.collectionLastUpdate.replaceAll(' ', 'T'));
        final next = DateTime.parse(_plugin.collectionNextUpdate.replaceAll(' ', 'T'));
        return next.difference(last).inMinutes;
      }
    } catch (_) {}
    return 30;
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// 切换全选/取消全选
  void _toggleSelectAll() {
    final newState = !_allEnabled;
    setState(() {
      _allEnabled = newState;
      for (final child in _plugin.childPlugins) {
        child.enabled = newState;
      }
    });
    final ctrl = inject<PluginsController>();
    unawaited(ctrl.savePlugins());
  }

  /// 分享合集
  void _shareCollection() {
    final jsonStr = json.encode({
      'exportedMediaSourceDataList': {
        'mediaSources': _plugin.childPlugins.map((p) {
          if (p.animekoConfig != null) {
            return {
              'factoryId': 'web-selector',
              'version': 2,
              'arguments': p.animekoConfig!.toJson(),
            };
          }
          return null;
        }).where((e) => e != null).toList(),
      },
    });
    // 生成分享链接
    final httpLink = jsonToShareUrl(jsonStr);
    final yhdmgzLink = jsonToKazumiBase64(jsonStr);

    Clipboard.setData(ClipboardData(text: httpLink));
    KazumiDialog.showToast(message: '分享链接已复制到剪贴板');

    // 显示分享选项
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制 HTTP 链接（可分享给好友）'),
              subtitle: Text(httpLink, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Clipboard.setData(ClipboardData(text: httpLink));
                Navigator.pop(ctx);
                KazumiDialog.showToast(message: 'HTTP 链接已复制');
              },
            ),
            ListTile(
              leading: const Icon(Icons.shield),
              title: const Text('复制 yhdmgz 协议链接（App 内使用）'),
              subtitle: Text(yhdmgzLink, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Clipboard.setData(ClipboardData(text: yhdmgzLink));
                Navigator.pop(ctx);
                KazumiDialog.showToast(message: 'yhdmgz 链接已复制');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final children = _plugin.childPlugins;

    return Scaffold(
      appBar: SysAppBar(
        title: Text(_plugin.name),
        actions: [
          // 手动刷新
          IconButton(
            onPressed: _updating ? null : _refreshCollection,
            tooltip: '立即更新',
            icon: _updating
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          // 分享
          IconButton(
            onPressed: _shareCollection,
            tooltip: '分享合集',
            icon: const Icon(Icons.share),
          ),
        ],
      ),
      body: Column(
        children: [
          // 统计信息卡片
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _buildStatsRow(colorScheme),
          ),
          // 更新信息栏 + 全选按钮
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.update, size: 14, color: colorScheme.primary),
                const SizedBox(width: 6),
                if (_plugin.collectionLastUpdate.isNotEmpty)
                  Text(
                    '上次: ${_plugin.collectionLastUpdate}',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                const Spacer(),
                if (_plugin.collectionNextUpdate.isNotEmpty)
                  Text(
                    '下次: ${_plugin.collectionNextUpdate}',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _toggleSelectAll,
                  icon: Icon(
                    _allEnabled ? Icons.select_all : Icons.deselect,
                    size: 14,
                  ),
                  label: Text(
                    _allEnabled ? '全关' : '全开',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          // 来源列表
          Expanded(
            child: children.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.library_books, size: 64, color: colorScheme.outline),
                        const SizedBox(height: 16),
                        Text('合集为空', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: children.length,
                    itemBuilder: (context, index) {
                      final child = children[index];
                      final searchUrl = child.searchURL.isNotEmpty
                          ? child.searchURL
                          : (child.animekoConfig?.searchConfig.searchUrl ?? '');

                      final tags = <Widget>[
                        RuleTag(
                          label: child.version,
                          background: colorScheme.secondaryContainer,
                          foreground: colorScheme.onSecondaryContainer,
                        ),
                        if (child.searchMode == 'css' || child.animekoConfig != null)
                          RuleTag(
                            label: 'CSS',
                            background: colorScheme.tertiaryContainer,
                            foreground: colorScheme.onTertiaryContainer,
                          ),
                        if (child.searchMode == 'rss')
                          RuleTag(
                            label: 'RSS',
                            background: colorScheme.primaryContainer,
                            foreground: colorScheme.onPrimaryContainer,
                          ),
                      ];

                      return RuleCard(
                        title: child.name,
                        tags: tags,
                        caption: _simplifyUrl(searchUrl),
                        trailing: IconButton(
                          icon: Icon(
                            child.enabled ? Icons.visibility : Icons.visibility_off,
                            color: child.enabled ? colorScheme.primary : colorScheme.outline,
                          ),
                          onPressed: () {
                            setState(() => child.enabled = !child.enabled);
                            final ctrl = inject<PluginsController>();
                            unawaited(ctrl.savePlugins());
                          },
                          tooltip: child.enabled ? '禁用' : '启用',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建统计信息行
  Widget _buildStatsRow(ColorScheme colorScheme) {
    final children = _plugin.childPlugins;
    final total = children.length;
    final enabled = children.where((p) => p.enabled).length;
    final disabled = total - enabled;
    final cssCount = children.where((p) => p.searchMode == 'css').length;
    final rssCount = children.where((p) => p.searchMode == 'rss').length;

    return Row(
      children: [
        _statItem(Icons.grid_view, '$total 个源', colorScheme.primary, colorScheme),
        const SizedBox(width: 16),
        _statItem(Icons.visibility, '$enabled 启用', Colors.green.shade600, colorScheme),
        const SizedBox(width: 16),
        _statItem(Icons.visibility_off, '$disabled 禁用', Colors.orange.shade600, colorScheme),
        const Spacer(),
        if (cssCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('CSS $cssCount', style: TextStyle(fontSize: 11, color: colorScheme.onTertiaryContainer)),
          ),
        const SizedBox(width: 6),
        if (rssCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('RSS $rssCount', style: TextStyle(fontSize: 11, color: colorScheme.onPrimaryContainer)),
          ),
      ],
    );
  }

  Widget _statItem(IconData icon, String label, Color color, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurface)),
      ],
    );
  }

  String _simplifyUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host + (uri.path.length > 30 ? '${uri.path.substring(0, 30)}...' : uri.path);
    } catch (_) {
      return url;
    }
  }
}

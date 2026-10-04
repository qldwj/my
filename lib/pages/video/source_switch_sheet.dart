import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';

/// 播放页内「切换播放源」底部面板：从底部弹出约 1/2 屏幕高，
/// 列出各规则的搜索结果，颜色点标识状态
/// （绿=可用 / 红=错误 / 蓝=需验证 / 紫=需登录 / 橙=无结果 / 灰=加载中）。
/// 点击某个结果 → `Navigator.pop((Plugin, SearchItem))`，由播放页切换源并继续播放。
class SourceSwitchSheet extends StatefulWidget {
  const SourceSwitchSheet({super.key, required this.controller});

  final VideoPageController controller;

  @override
  State<SourceSwitchSheet> createState() => _SourceSwitchSheetState();
}

class _SourceSwitchSheetState extends State<SourceSwitchSheet> {
  PluginsController? _pluginsController;

  @override
  void initState() {
    super.initState();
    _pluginsController = widget.controller.searchPluginsController ??
        inject<PluginsController>();
  }

  Plugin? _findPlugin(String name) {
    final pc = _pluginsController;
    if (pc == null) return null;
    for (final p in pc.pluginList) {
      if (p.name == name) return p;
      if (p.isCollection) {
        for (final c in p.childPlugins) {
          if (c.name == name) return c;
        }
      }
    }
    return null;
  }

  Color _statusColor(PluginSearchStatus st) {
    switch (st) {
      case PluginSearchStatus.success:
        return Colors.green;
      case PluginSearchStatus.noResult:
        return Colors.orange;
      case PluginSearchStatus.captcha:
        return Colors.blue;
      case PluginSearchStatus.error:
        return Colors.red;
      case PluginSearchStatus.login:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.controller.searchInfoController;
    final responses =
        (info?.pluginSearchResponseList ?? const <PluginSearchResponse>[])
            .where((r) => r.data.isNotEmpty)
            .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.52,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '切换播放源',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: responses.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LoadingIndicator(),
                              SizedBox(height: 12),
                              Text('正在检索播放源…'),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: responses.length,
                        itemBuilder: (context, i) =>
                            _PluginBlock(
                          pluginName: responses[i].pluginName,
                          items: responses[i].data,
                          statusColor: _statusColor(
                              info?.pluginSearchStatus[responses[i].pluginName] ??
                                  PluginSearchStatus.pending),
                          onSelect: (item) {
                            final plugin = _findPlugin(responses[i].pluginName);
                            if (plugin == null) return;
                            Navigator.of(context).pop((plugin, item));
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PluginBlock extends StatelessWidget {
  const _PluginBlock({
    required this.pluginName,
    required this.items,
    required this.statusColor,
    required this.onSelect,
  });

  final String pluginName;
  final List<SearchItem> items;
  final Color statusColor;
  final void Function(SearchItem) onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  pluginName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          for (final item in items)
            ListTile(
              dense: true,
              title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onSelect(item),
            ),
        ],
      ),
    );
  }
}

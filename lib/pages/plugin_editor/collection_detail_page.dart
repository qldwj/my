import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/utils/episode_url.dart';

/// 合集详情页面
///
/// 展示一个合集（Animeko Collection）中包含的所有动漫来源规则。
class CollectionDetailPage extends StatelessWidget {
  const CollectionDetailPage({super.key, required this.plugin});

  final Plugin plugin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final children = plugin.childPlugins;

    return Scaffold(
      appBar: SysAppBar(
        title: Text(plugin.name),
      ),
      body: Column(
        children: [
          // 更新信息栏
          if (plugin.collectionLastUpdate.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Icon(Icons.update, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '上次更新: ${plugin.collectionLastUpdate}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (plugin.collectionNextUpdate.isNotEmpty)
                    Text(
                      '下次更新: ${plugin.collectionNextUpdate}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
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
                        Icon(Icons.library_books,
                            size: 64, color: colorScheme.outline),
                        const SizedBox(height: 16),
                        Text('合集为空',
                            style: TextStyle(color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: children.length,
                    itemBuilder: (context, index) {
                      final child = children[index];
                      // 获取搜索 URL 的显示信息
                      final searchUrl = child.searchURL.isNotEmpty
                          ? child.searchURL
                          : (child.animekoConfig?.searchConfig.searchUrl ?? '');

                      // 构建标签
                      final tags = <Widget>[
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
                          icon: Icon(Icons.visibility,
                              color: child.enabled
                                  ? colorScheme.primary
                                  : colorScheme.outline),
                          onPressed: () {
                            // 切换子规则的启用状态
                            child.enabled = !child.enabled;
                            // 强制刷新
                            (context as Element).markNeedsBuild();
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

  String _simplifyUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host + (uri.path.length > 30 ? '${uri.path.substring(0, 30)}...' : uri.path);
    } catch (_) {
      return url;
    }
  }
}

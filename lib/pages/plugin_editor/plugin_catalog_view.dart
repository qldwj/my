import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/source_rating_widget.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/pages/plugin_editor/plugin_update_actions.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/storage/storage.dart';

enum PluginCatalogSort { lastUpdate, name }

/// 官方 2.3.7 新增：目录过滤维度（全部 / 已安装 / 可更新）
enum _CatalogFilter { all, installed, updates }

class PluginCatalogView extends StatefulWidget {
  const PluginCatalogView({
    super.key,
    required this.controller,
    this.sort = PluginCatalogSort.lastUpdate,
    this.listPadding = const EdgeInsets.symmetric(horizontal: 8),
    this.showRefreshButton = false,
    this.compactLastUpdate = false,
    this.errorMessage = '无法访问规则仓库',
    this.showRating = true,
  });

  final PluginsController controller;
  final PluginCatalogSort sort;
  final EdgeInsetsGeometry listPadding;
  final bool showRefreshButton;
  final bool compactLastUpdate;
  final String errorMessage;

  /// 是否在源卡片上显示稳定性评分（规则仓/首页向导显示，规则管理页可关）
  final bool showRating;

  @override
  State<PluginCatalogView> createState() => PluginCatalogViewState();
}

class PluginCatalogViewState extends State<PluginCatalogView> {
  bool _loading = true;
  bool _loadFailed = false;

  /// 官方 2.3.7 新增：本地搜索关键字 + 过滤维度
  final _search = TextEditingController();
  _CatalogFilter _filter = _CatalogFilter.all;

  PluginsController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_controller.isPluginCatalogFresh) {
      _loading = false;
    } else {
      unawaited(_loadPluginCatalog());
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPluginCatalog({bool forceRefresh = false}) async {
    try {
      if (forceRefresh) {
        await _controller.refreshPluginCatalog();
      } else {
        await _controller.ensurePluginCatalog();
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void refresh() {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    unawaited(_loadPluginCatalog(forceRefresh: true));
  }

  Future<void> _toggleGitProxyAndRefresh() async {
    final enableGitProxy = GStorage.getSetting(SettingsKeys.enableGitProxy);
    await GStorage.putSetting(SettingsKeys.enableGitProxy, !enableGitProxy);
    if (!mounted) return;
    refresh();
  }

  /// 官方 2.3.7 新增：按搜索关键字 + 过滤维度过滤后再排序。
  /// 保留 my 原有 widget.sort 排序契约（由外层 AppBar 切换）。
  List<PluginHTTPItem> _visibleItems() {
    final query = _search.text.trim().toLowerCase();
    final items = _controller.pluginHTTPList.where((item) {
      final matchesQuery = query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.author.toLowerCase().contains(query);
      if (!matchesQuery) return false;
      return switch (_filter) {
        _CatalogFilter.all => true,
        _CatalogFilter.installed =>
          _controller.pluginStatus(item) != PluginCatalogItemStatus.install,
        _CatalogFilter.updates =>
          _controller.pluginStatus(item) == PluginCatalogItemStatus.update,
      };
    }).toList();
    switch (widget.sort) {
      case PluginCatalogSort.lastUpdate:
        items.sort((a, b) => b.lastUpdate.compareTo(a.lastUpdate));
      case PluginCatalogSort.name:
        items.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    }
    return items;
  }

  /// 官方 2.3.7 新增：搜索框 + 全部/已安装/可更新 过滤条。
  /// 仅在独立规则仓库页（showRefreshButton=false）展示；onboarding 紧凑页
  /// （showRefreshButton=true）保持 my 原有紧凑列表，不挤压引导布局。
  Widget _buildCatalogHeader() {
    final catalog = _controller.pluginHTTPList;
    final installedCount = catalog
        .where((p) =>
            _controller.pluginStatus(p) != PluginCatalogItemStatus.install)
        .length;
    final updateCount = catalog
        .where((p) => _controller.pluginStatus(p) == PluginCatalogItemStatus.update)
        .length;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索规则或作者',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in [
                    (_CatalogFilter.all, '全部 ${catalog.length}'),
                    (_CatalogFilter.installed, '已安装 $installedCount'),
                    (_CatalogFilter.updates, '可更新 $updateCount'),
                  ])
                    FilterChip(
                      label: Text(entry.$2),
                      selected: _filter == entry.$1,
                      onSelected: (_) => setState(() => _filter = entry.$1),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPluginList() {
    return Observer(builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      final items = _visibleItems();

      final listView = ListView.builder(
        padding: widget.listPadding,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final status = _controller.pluginStatus(item);
          return RuleCard(
            title: item.name,
            iconUrl: item.icon.isNotEmpty ? item.icon : null,
            tags: [
              RuleTag(
                label: item.version,
                background: colorScheme.secondaryContainer,
                foreground: colorScheme.onSecondaryContainer,
              ),
              if (item.needLogin)
                RuleTag(
                  label: '需要登录',
                  background: colorScheme.errorContainer,
                  foreground: colorScheme.onErrorContainer,
                ),
              if (item.antiCrawlerEnabled)
                RuleTag(
                  label: '需要验证',
                  background: colorScheme.tertiaryContainer,
                  foreground: colorScheme.onTertiaryContainer,
                ),
            ],
            caption:
                item.lastUpdate > 0 ? _formatLastUpdate(item.lastUpdate) : null,
            ratingSourceId: widget.showRating ? item.name : null,
            trailing: RuleCardActionButton(
              label: switch (status) {
                PluginCatalogItemStatus.install => '安装',
                PluginCatalogItemStatus.installed => '已安装',
                PluginCatalogItemStatus.update => '更新',
              },
              onPressed: status == PluginCatalogItemStatus.installed
                  ? null
                  : () async {
                      final result = await updatePluginWithFeedback(
                        _controller,
                        item.name,
                        installing: status == PluginCatalogItemStatus.install,
                      );
                      if (result == PluginUpdateResult.updated && mounted) {
                        setState(() {});
                      }
                    },
            ),
          );
        },
      );

      // onboarding 紧凑模式不展示搜索/筛选头；独立规则仓库页展示。
      if (widget.showRefreshButton) {
        return listView;
      }
      return Column(
        children: [
          _buildCatalogHeader(),
          Expanded(child: listView),
        ],
      );
    });
  }

  String _formatLastUpdate(int millisecondsSinceEpoch) {
    final value =
        DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch).toString();
    if (widget.compactLastUpdate) {
      return value.split(' ')[0];
    }
    return '更新时间: ${value.split('.')[0]}';
  }

  Widget _buildLoadError() {
    final enableGitProxy = GStorage.getSetting(SettingsKeys.enableGitProxy);
    return Center(
      child: GeneralErrorWidget(
        errMsg:
            '${widget.errorMessage}\n${enableGitProxy ? '规则仓库镜像已启用' : '规则仓库镜像已禁用'}',
        actions: [
          GeneralErrorButton(
            onPressed: () => unawaited(_toggleGitProxyAndRefresh()),
            text: enableGitProxy ? '禁用规则镜像' : '启用规则镜像',
          ),
          GeneralErrorButton(onPressed: refresh, text: '刷新'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: LoadingIndicator());
    }
    if (_loadFailed) {
      return _buildLoadError();
    }
    if (_controller.pluginHTTPList.isEmpty) {
      return const Center(child: Text('规则仓库中暂无规则'));
    }
    return _buildPluginList();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showRefreshButton) {
      return _buildBody();
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              onPressed: refresh,
              tooltip: '刷新规则列表',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(child: _buildBody()),
      ],
    );
  }
}

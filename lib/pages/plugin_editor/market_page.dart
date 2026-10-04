import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/request/apis/plugin_market_api.dart';

/// 规则市场页（对接 qlyyz.xyz/json/ 文件仓库）
///
/// - 任何人可上传规则（上传入口在规则管理页）
/// - 区分管理员上传 / 用户上传
/// - 管理员上传的规则标"官方"，用户上传标"用户上传"
/// - 下架由管理员在网页端（json 仓库后台）操作
/// 内部哨兵值，表示"全部"分类（不直接展示，展示时本地化）。
const String _allCategorySentinel = '__all_rules__';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key, required this.controller});

  final PluginsController controller;

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  bool _loading = true;
  bool _loadFailed = false;
  List<MarketRuleItem> _items = const [];
  String _selectedCategory = _allCategorySentinel;

  /// 从列表聚合出的分类（保持出现顺序）
  List<String> get _categories {
    final seen = <String>{};
    final result = <String>[_allCategorySentinel];
    for (final item in _items) {
      if (seen.add(item.category)) {
        result.add(item.category);
      }
    }
    return result;
  }

  List<MarketRuleItem> get _filteredItems {
    if (_selectedCategory == _allCategorySentinel) return _items;
    return _items.where((e) => e.category == _selectedCategory).toList();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final items = await PluginMarketApi.fetchList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _install(MarketRuleItem item) async {
    final l10n = AppLocalizations.of(context)!;
    KazumiDialog.showToast(message: l10n.setFLoadingRule);
    try {
      final content = await PluginMarketApi.fetchRule(item.file);
      final plugin = Plugin.fromJson(
          jsonDecode(content) as Map<String, dynamic>);
      // 同名规则是否已存在
      final exists = widget.controller.pluginList
          .any((p) => p.name.toLowerCase() == plugin.name.toLowerCase());
      final confirm = await KazumiDialog.show<bool>(
        builder: (context) {
          final dl10n = AppLocalizations.of(context)!;
          return AlertDialog(
            title: Text(dl10n.setFInstallRule),
            content: Text(
              '${dl10n.setFRuleNameVersion(name: plugin.name, version: plugin.version)}\n'
              '${exists ? dl10n.setFRuleOverwriteExisting : dl10n.setFRuleManageAfterInstall}',
            ),
            actions: [
              TextButton(
                onPressed: () => KazumiDialog.dismiss(popWith: false),
                child: Text(dl10n.cancel),
              ),
              FilledButton(
                onPressed: () => KazumiDialog.dismiss(popWith: true),
                child: Text(dl10n.setFInstall),
              ),
            ],
          );
        },
      );
      if (confirm != true) return;
      await widget.controller.updatePlugin(plugin);
      if (mounted) {
        KazumiDialog.showToast(message: l10n.setFInstallSuccess);
      }
    } catch (e) {
      if (mounted) {
        KazumiDialog.showToast(message: l10n.setFInstallFail(error: e.toString()));
      }
    }
  }

  Widget _buildList() {
    final l10n = AppLocalizations.of(context)!;
    final items = _filteredItems;
    if (items.isEmpty) {
      return Center(child: Text(l10n.setFMarketEmpty));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final colorScheme = Theme.of(context).colorScheme;
        return RuleCard(
          title: item.origin.replaceAll(RegExp(r'\.json$'), ''),
          tags: [
            RuleTag(
              label: item.isAdminUpload ? l10n.setFOfficial : l10n.setFUserUploaded,
              background: item.isAdminUpload
                  ? colorScheme.primaryContainer
                  : colorScheme.tertiaryContainer,
              foreground: item.isAdminUpload
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onTertiaryContainer,
            ),
            RuleTag(
              label: item.category,
              background: colorScheme.secondaryContainer,
              foreground: colorScheme.onSecondaryContainer,
            ),
          ],
          caption: '${item.time}${item.uid.isNotEmpty ? ' · ${item.uid}' : ''}',
          trailing: RuleCardActionButton(
            label: l10n.setFInstall,
            onPressed: () => _install(item),
          ),
        );
      },
    );
  }

  /// 顶部分类筛选条（横向滚动）
  Widget _buildCategoryBar() {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final categories = _categories;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final c = categories[index];
          final selected = c == _selectedCategory;
          return ChoiceChip(
            label: Text(c == _allCategorySentinel ? l10n.setFAll : c),
            selected: selected,
            onSelected: (_) => setState(() => _selectedCategory = c),
            selectedColor: colorScheme.primaryContainer,
            labelStyle: TextStyle(
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: LoadingIndicator());
    }
    if (_loadFailed) {
      return Center(
        child: GeneralErrorWidget(
          errMsg: l10n.setFMarketUnreachable,
          actions: [
            GeneralErrorButton(onPressed: _load, text: l10n.retry),
          ],
        ),
      );
    }
    return _buildList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SysAppBar(
        title: Text(l10n.setFRuleMarket),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: l10n.setCRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_loading && !_loadFailed && _items.isNotEmpty)
            _buildCategoryBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

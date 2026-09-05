import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/request/apis/plugin_market_api.dart';

/// 规则市场页（对接 qlyyz.xyz/json/ 文件仓库）
///
/// - 任何人可上传规则（上传入口在规则管理页）
/// - 区分管理员上传 / 用户上传
/// - 管理员上传的规则标"官方"，用户上传标"用户上传"
/// - 下架由管理员在网页端（json 仓库后台）操作
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
  String _selectedCategory = '全部';

  /// 从列表聚合出的分类（保持出现顺序）
  List<String> get _categories {
    final seen = <String>{};
    final result = <String>['全部'];
    for (final item in _items) {
      if (seen.add(item.category)) {
        result.add(item.category);
      }
    }
    return result;
  }

  List<MarketRuleItem> get _filteredItems {
    if (_selectedCategory == '全部') return _items;
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
    KazumiDialog.showToast(message: '正在获取规则…');
    try {
      final content = await PluginMarketApi.fetchRule(item.file);
      final plugin = Plugin.fromJson(
          jsonDecode(content) as Map<String, dynamic>);
      // 同名规则是否已存在
      final exists = widget.controller.pluginList
          .any((p) => p.name.toLowerCase() == plugin.name.toLowerCase());
      final confirm = await KazumiDialog.show<bool>(
        builder: (context) => AlertDialog(
          title: const Text('安装规则'),
          content: Text(
            '规则「${plugin.name}」v${plugin.version}\n'
            '${exists ? '本机已存在同名规则，将覆盖。' : '安装后可在规则管理中管理。'}',
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(popWith: false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => KazumiDialog.dismiss(popWith: true),
              child: const Text('安装'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      await widget.controller.updatePlugin(plugin);
      if (mounted) {
        KazumiDialog.showToast(message: '安装成功 ✅');
      }
    } catch (e) {
      if (mounted) {
        KazumiDialog.showToast(message: '安装失败: $e');
      }
    }
  }

  Widget _buildList() {
    final items = _filteredItems;
    if (items.isEmpty) {
      return const Center(child: Text('市场中还没有规则\n\n在规则管理页点「上传到市场」即可分享你的规则'));
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
              label: item.isAdminUpload ? '官方' : '用户上传',
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
            label: '安装',
            onPressed: () => _install(item),
          ),
        );
      },
    );
  }

  /// 顶部分类筛选条（横向滚动）
  Widget _buildCategoryBar() {
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
            label: Text(c),
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
      return Center(
        child: GeneralErrorWidget(
          errMsg: '无法访问规则市场\n请确认服务器 qlyyz.xyz/json/ 已部署',
          actions: [
            GeneralErrorButton(onPressed: _load, text: '重试'),
          ],
        ),
      );
    }
    return _buildList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('规则市场'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: '刷新',
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

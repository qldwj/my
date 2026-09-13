import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/storage/storage.dart';

enum _SortMode { recent, name, rating, airDate }

extension _SortLabel on _SortMode {
  String get label => switch (this) {
    _SortMode.recent => '最近变更',
    _SortMode.name => '追番名',
    _SortMode.rating => '评分最高',
    _SortMode.airDate => '开播时间',
  };
}

class CollectPage extends StatefulWidget {
  const CollectPage({super.key, required this.controller});
  final CollectController controller;

  @override
  State<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<CollectPage> {
  CollectController get ctrl => widget.controller;
  int _selectedType = 0; // 0=全部
  _SortMode _sortMode = _SortMode.recent;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    ctrl.loadCollectibles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CollectedBangumi> get _filtered {
    var list = ctrl.collectibles.toList();
    // 按状态筛选
    if (_selectedType != 0) {
      list = list.where((c) => c.type == _selectedType).toList();
    }
    // 按搜索筛选
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((c) =>
        c.bangumiItem.name.toLowerCase().contains(q) ||
        c.bangumiItem.nameCn.toLowerCase().contains(q)
      ).toList();
    }
    // 排序
    switch (_sortMode) {
      case _SortMode.recent:
        list.sort((a, b) => b.time.compareTo(a.time));
      case _SortMode.name:
        list.sort((a, b) => a.bangumiItem.nameCn.compareTo(b.bangumiItem.nameCn));
      case _SortMode.rating:
        list.sort((a, b) => b.bangumiItem.ratingScore.compareTo(a.bangumiItem.ratingScore));
      case _SortMode.airDate:
        list.sort((a, b) => b.bangumiItem.airDate.compareTo(a.bangumiItem.airDate));
    }
    return list;
  }

  int _countByType(int type) {
    if (type == 0) return ctrl.collectibles.length;
    return ctrl.collectibles.where((c) => c.type == type).length;
  }

  Future<void> _syncAll() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await ctrl.syncCollectibles(showSuccessToast: false);
      if (mounted) KazumiDialog.showToast(message: '同步完成');
    } catch (e) {
      if (mounted) KazumiDialog.showToast(message: '同步失败: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text(
          '追番',
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        needTopOffset: false,
        actions: [
          // 日历
          IconButton(
            tooltip: '日历',
            icon: const Icon(Icons.calendar_month_rounded, size: 22),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const _CollectCalendarPlaceholder(),
              ),
            ),
          ),
          // 文件夹
          IconButton(
            tooltip: '文件夹',
            icon: const Icon(Icons.folder_copy_rounded, size: 22),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const _CollectFolderPlaceholder(),
              ),
            ),
          ),
          // 同步
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _syncing ? null : _syncAll,
              icon: _syncing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: const Text('同步'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 搜索栏 + 排序 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: '搜索收藏番剧...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 排序选择
                PopupMenuButton<_SortMode>(
                  icon: Icon(Icons.sort_rounded, color: colors.onSurfaceVariant),
                  onSelected: (v) => setState(() => _sortMode = v),
                  itemBuilder: (_) => _SortMode.values.map((m) =>
                    PopupMenuItem(
                      value: m,
                      child: Row(
                        children: [
                          if (m == _sortMode)
                            Icon(Icons.check, size: 18, color: colors.primary)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(m.label),
                        ],
                      ),
                    ),
                  ).toList(),
                ),
              ],
            ),
          ),

          // ── 状态标签 ──
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              children: [
                _buildTypeChip(0, '全部', _countByType(0)),
                _buildTypeChip(1, '在看', _countByType(1)),
                _buildTypeChip(2, '想看', _countByType(2)),
                _buildTypeChip(4, '看过', _countByType(4)),
                _buildTypeChip(3, '搁置', _countByType(3)),
                _buildTypeChip(5, '抛弃', _countByType(5)),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── 番剧列表 ──
          Expanded(
            child: Observer(builder: (_) {
              final items = _filtered;
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.collections_bookmark_rounded,
                          size: 64, color: colors.outlineVariant),
                      const SizedBox(height: 16),
                      Text('暂无收藏', style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: items.length,
                itemBuilder: (context, index) => _CollectTile(
                  item: items[index],
                  onTypeChanged: (type) async {
                    await ctrl.addCollect(items[index].bangumiItem, type: type);
                    setState(() {});
                  },
                  onDelete: () async {
                    await ctrl.deleteCollect(items[index].bangumiItem);
                    setState(() {});
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(int type, String label, int count) {
    final selected = _selectedType == type;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label $count'),
        selected: selected,
        onSelected: (_) => setState(() => _selectedType = type),
        selectedColor: colors.primaryContainer,
        labelStyle: TextStyle(
          color: selected ? colors.onPrimaryContainer : colors.onSurface,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        side: BorderSide.none,
      ),
    );
  }
}

/// ── 单个番剧条目 ──
class _CollectTile extends StatefulWidget {
  const _CollectTile({
    required this.item,
    required this.onTypeChanged,
    required this.onDelete,
  });

  final CollectedBangumi item;
  final ValueChanged<int> onTypeChanged;
  final VoidCallback onDelete;

  @override
  State<_CollectTile> createState() => _CollectTileState();
}

class _CollectTileState extends State<_CollectTile> {
  bool _expanded = false;

  String _typeName(int type) => CollectType.fromValue(type).label;

  Color _typeColor(int type, ColorScheme colors) => switch (type) {
    1 => Colors.green,
    2 => Colors.blue,
    4 => Colors.purple,
    3 => Colors.orange,
    5 => Colors.red,
    _ => colors.outline,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bangumi = widget.item.bangumiItem;
    final currentType = widget.item.type;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () => context.pushNamed('/info/', arguments: bangumi),
        child: Column(
          children: [
            // 主行：封面 + 名称 + 状态
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // 封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: NetworkImgLayer(
                      width: 56,
                      height: 72,
                      src: bangumi.images['large'] ?? '',
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 名称 + 评分
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bangumi.nameCn.isNotEmpty ? bangumi.nameCn : bangumi.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text('${bangumi.ratingScore}',
                                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 状态标签 + 展开
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _typeColor(currentType, colors).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _typeName(currentType),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _typeColor(currentType, colors),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 展开区域：快速切换状态
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTypeButton(1, '在看', currentType),
                        _buildTypeButton(2, '想看', currentType),
                        _buildTypeButton(4, '看过', currentType),
                        _buildTypeButton(3, '搁置', currentType),
                        _buildTypeButton(5, '抛弃', currentType),
                        _buildDeleteButton(),
                      ],
                    ),
                  ],
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeButton(int type, String label, int currentType) {
    final colors = Theme.of(context).colorScheme;
    final selected = currentType == type;
    return GestureDetector(
      onTap: selected ? null : () => widget.onTypeChanged(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? colors.surfaceContainerHighest
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: colors.outline, width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(
              fontSize: 13,
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
            )),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_rounded, size: 14, color: colors.onSurface),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: widget.onDelete,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('取消收藏',
            style: TextStyle(fontSize: 13, color: colors.onErrorContainer)),
      ),
    );
  }
}

// ── 占位页面 ──
class _CollectCalendarPlaceholder extends StatelessWidget {
  const _CollectCalendarPlaceholder();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('日历')),
    body: const Center(child: Text('日历功能')),
  );
}

class _CollectFolderPlaceholder extends StatelessWidget {
  const _CollectFolderPlaceholder();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('文件夹')),
    body: const Center(child: Text('文件夹功能')),
  );
}

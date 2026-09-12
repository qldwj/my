import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/auth_service.dart';
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
    _showSyncDialog();
  }

  void _showSyncDialog() {
    final services = <_SyncStep>[];
    if (GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty) {
      services.add(_SyncStep('Bangumi', Icons.brightness_6_rounded));
    }
    if (GStorage.getSetting(SettingsKeys.webDavURL).trim().isNotEmpty) {
      services.add(_SyncStep('WebDAV', Icons.cloud_sync_rounded));
    }
    if (AuthService.isLoggedIn) {
      services.add(_SyncStep('樱花动漫', Icons.wb_twilight_rounded));
    }

    if (services.isEmpty) {
      KazumiDialog.showToast(message: '请先在同步设置中配置服务');
      return;
    }

    int conflictMode = 0;
    bool syncing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('同步收藏', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('当前能同步 ${services.length} 个服务', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                for (var i = 0; i < services.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(services[i].icon, size: 20, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(services[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('第${i + 1}步', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text('冲突方式', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<int>(
                        title: const Text('本地优先', style: TextStyle(fontSize: 13)),
                        subtitle: const Text('先上传再下载', style: TextStyle(fontSize: 11)),
                        value: 0, groupValue: conflictMode,
                        onChanged: (v) => setSheetState(() => conflictMode = v ?? 0),
                        dense: true, contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<int>(
                        title: const Text('服务器优先', style: TextStyle(fontSize: 13)),
                        subtitle: const Text('先下载再上传', style: TextStyle(fontSize: 11)),
                        value: 1, groupValue: conflictMode,
                        onChanged: (v) => setSheetState(() => conflictMode = v ?? 0),
                        dense: true, contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: syncing ? null : () async {
                      setSheetState(() => syncing = true);
                      try {
                        for (final step in services) {
                          if (step.name == 'WebDAV') {
                            await ctrl.syncCollectibles(showSuccessToast: false);
                          }
                        }
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          KazumiDialog.showToast(message: '同步完成');
                        }
                      } catch (e) {
                        if (ctx.mounted) KazumiDialog.showToast(message: '同步失败: $e');
                      } finally {
                        if (mounted) setSheetState(() => syncing = false);
                      }
                    },
                    icon: syncing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync_rounded),
                    label: Text(syncing ? '同步中...' : '开始同步'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 24,
                        color: colors.onSurfaceVariant,
                      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              fontSize: 14,
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
            )),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_rounded, size: 16, color: colors.onSurface),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('取消收藏',
            style: TextStyle(fontSize: 14, color: colors.onErrorContainer)),
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

class _SyncStep {
  final String name;
  final IconData icon;
  _SyncStep(this.name, this.icon);
}

import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/collect/collect_folder_service.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 收藏分组管理页
///
/// - 新建 / 重命名 / 删除分组
/// - 点击分组进入查看该分组内的番剧
/// - 分组内长按卡片可移出分组
class CollectFolderPage extends StatefulWidget {
  const CollectFolderPage({super.key});

  @override
  State<CollectFolderPage> createState() => _CollectFolderPageState();
}

class _CollectFolderPageState extends State<CollectFolderPage> {
  Map<String, List<int>> _folders = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _folders = CollectFolderService.loadAll();
    });
  }

  Future<void> _createFolder() async {
    final name = await _showNameDialog(title: '新建分组', hint: '如：待补番 / 二刷 / 和朋友一起看');
    if (name == null || name.isEmpty) return;
    final ok = await CollectFolderService.createFolder(name);
    if (!mounted) return;
    if (ok) {
      _reload();
      KazumiDialog.showToast(message: '✅ 已创建分组「$name」');
    } else {
      KazumiDialog.showToast(message: '分组「$name」已存在或名称无效');
    }
  }

  Future<void> _renameFolder(String oldName) async {
    final name =
        await _showNameDialog(title: '重命名分组', hint: '新名称', initial: oldName);
    if (name == null || name.isEmpty) return;
    final ok = await CollectFolderService.renameFolder(oldName, name);
    if (!mounted) return;
    if (ok) {
      _reload();
      KazumiDialog.showToast(message: '✅ 已重命名为「$name」');
    } else {
      KazumiDialog.showToast(message: '名称无效或已存在同名分组');
    }
  }

  Future<void> _deleteFolder(String name) async {
    final confirm = await KazumiDialog.show<bool>(
      builder: (context) => AlertDialog(
        title: Text('删除分组「$name」'),
        content: const Text('仅删除分组关系，收藏本身不会删除。确定？'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await CollectFolderService.deleteFolder(name);
    _reload();
    if (mounted) KazumiDialog.showToast(message: '已删除分组「$name」');
  }

  Future<String?> _showNameDialog({
    required String title,
    required String hint,
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _openFolder(String name, List<int> ids) async {
    if (ids.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FolderDetailPage(name: name, ids: ids),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = _folders.entries.toList();
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('收藏分组'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(rootNavigatorKey.currentContext!)
              .maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: '新建分组',
            onPressed: _createFolder,
            icon: const Icon(Icons.create_new_folder_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFolder,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建分组'),
      ),
      body: entries.isEmpty
          ? const Center(
              child: GeneralEmptyState(
                icon: Icons.folder_outlined,
                title: '还没有收藏分组',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '分组是本地功能，不会影响 Bangumi / 云端同步',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
                const SizedBox(height: 8),
                for (final entry in entries) ...[
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(Icons.folder_rounded,
                            color: colorScheme.onPrimaryContainer),
                      ),
                      title: Text(
                        entry.key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('${entry.value.length} 部番剧'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'open':
                              _openFolder(entry.key, entry.value);
                            case 'rename':
                              _renameFolder(entry.key);
                            case 'clear':
                              CollectFolderService.clearFolder(entry.key);
                              _reload();
                            case 'delete':
                              _deleteFolder(entry.key);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                              value: 'open', child: Text('查看番剧')),
                          const PopupMenuItem(
                              value: 'rename', child: Text('重命名')),
                          const PopupMenuItem(
                              value: 'clear', child: Text('清空分组')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('删除分组')),
                        ],
                      ),
                      onTap: () => _openFolder(entry.key, entry.value),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// 分组内番剧详情（网格展示）
class _FolderDetailPage extends StatefulWidget {
  const _FolderDetailPage({required this.name, required this.ids});

  final String name;
  final List<int> ids;

  @override
  State<_FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<_FolderDetailPage> {
  late List<BangumiItem> _items;

  @override
  void initState() {
    super.initState();
    _items = _loadItems();
  }

  List<BangumiItem> _loadItems() {
    // 从收藏里按 subjectId 找回 BangumiItem（分组只存 id）
    final collectibles = GStorage.collectibles.values
        .where((c) => widget.ids.contains(c.bangumiItem.id))
        .toList()
      ..sort((a, b) => b.time.millisecondsSinceEpoch
          .compareTo(a.time.millisecondsSinceEpoch));
    return collectibles.map((c) => c.bangumiItem).toList();
  }

  void _reload() {
    setState(() {
      _items = _loadItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        title: Text('分组「${widget.name}」'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(rootNavigatorKey.currentContext!)
              .maybePop(),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'clear':
                  await CollectFolderService.clearFolder(widget.name);
                  _reload();
                  if (mounted) KazumiDialog.showToast(message: '已清空分组');
                case 'delete':
                  await CollectFolderService.deleteFolder(widget.name);
                  if (mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear', child: Text('清空分组')),
              PopupMenuItem(value: 'delete', child: Text('删除分组')),
            ],
          ),
        ],
      ),
      body: _items.isEmpty
          ? Center(
              child: GeneralEmptyState(
                icon: Icons.folder_open_rounded,
                title: '分组内暂无番剧',
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width > 800 ? 6 : 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: MediaQuery.sizeOf(context).width / 3 / 0.65 + 40,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Stack(
                  children: [
                    BangumiCardV(bangumiItem: item, canTap: true),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: GestureDetector(
                        onTap: () async {
                          await CollectFolderService.removeFromFolder(
                              widget.name, item.id);
                          _reload();
                          if (mounted) {
                            KazumiDialog.showToast(message: '已移出「${widget.name}」');
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withOpacity(0.85),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, size: 16, color: colorScheme.error),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

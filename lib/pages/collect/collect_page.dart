import 'dart:async';

import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/modules/collect/collect_sync_plan.dart';
import 'package:kazumi/services/collect/collect_folder_service.dart';
import 'package:kazumi/pages/collect/collect_folder_page.dart';
import 'package:kazumi/pages/collect/collect_calendar_page.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/kazumi_sync_service.dart';
import 'package:kazumi/services/shortcut_service.dart';

class CollectPage extends StatefulWidget {
  const CollectPage({
    super.key,
    required this.controller,
  });

  final CollectController controller;

  @override
  State<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<CollectPage>
    with SingleTickerProviderStateMixin {
  CollectController get collectController => widget.controller;
  TabController? tabController;
  bool showDelete = false;
  bool syncCollectiblesing = false;

  /// 当前分组筛选（null = 全部）
  String? _activeFolder;

  Future<bool> _syncBangumiWithProgress({
    required GlobalKey<_FullSyncProgressDialogState> progressDialogKey,
  }) async {
    progressDialogKey.currentState?.update('准备同步 Bangumi 收藏...', null);

    await Future<void>.delayed(const Duration(milliseconds: 80));

    return collectController.syncCollectiblesBangumi(
      showSuccessToast: false,
      onProgress: (message, current, total) {
        progressDialogKey.currentState?.update(
          total > 0 ? '$message ($current/$total)' : message,
          total > 0 ? (current / total).clamp(0.0, 1.0).toDouble() : null,
        );
      },
    );
  }

  void _showFullSyncProgressDialog({
    required GlobalKey<_FullSyncProgressDialogState> progressDialogKey,
  }) {
    unawaited(KazumiDialog.show(
      clickMaskDismiss: false,
      builder: (context) => _FullSyncProgressDialog(key: progressDialogKey),
    ));
  }

  String _buildFullSyncSummary({
    required CollectSyncPlan plan,
    required bool webDavSynced,
    required bool bangumiSynced,
    required bool webDavUploaded,
    bool kazumiSynced = false,
  }) {
    final List<String> states = [];
    if (plan.shouldSyncKazumi) {
      states.add(kazumiSynced ? '樱花服务器 已同步' : '樱花服务器 未完成');
    }
    if (plan.shouldSyncWebDavCollectibles) {
      states.add(webDavSynced ? 'WebDav 已同步' : 'WebDav 未完成');
    }
    if (plan.shouldSyncBangumi) {
      states.add(bangumiSynced ? 'Bangumi 已同步' : 'Bangumi 未完成');
    }
    if (plan.shouldSyncWebDavCollectibles &&
        plan.shouldSyncBangumi &&
        webDavSynced &&
        bangumiSynced) {
      states.add(webDavUploaded ? 'WebDav 已回传最新数据' : 'WebDav 未回传最新数据');
    }
    return states.join('，');
  }

  /// 长按卡片：分组 + 桌面快捷方式菜单
  Future<void> _showShortcutMenu(BangumiItem bangumiItem) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('加入分组'),
              subtitle: const Text('把这部番整理到自定义分组'),
              onTap: () => Navigator.pop(context, 'folder'),
            ),
            ListTile(
              leading: const Icon(Icons.add_to_home_screen_rounded),
              title: const Text('添加到桌面快捷方式'),
              subtitle: const Text('点击快捷方式可直接打开并播放该番剧'),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (action == 'folder') {
      await _showFolderPicker(bangumiItem);
      return;
    }
    if (action != 'pin' || !mounted) return;
    final ok = await ShortcutService.pinShortcut(
      id: bangumiItem.id,
      name: bangumiItem.nameCn.isNotEmpty
          ? bangumiItem.nameCn
          : bangumiItem.name,
      episode: 0,
      adapterName: '',
    );
    if (!mounted) return;
    KazumiDialog.showToast(
      message: ok
          ? '请在桌面确认添加快捷方式'
          : '添加失败（需 Android 8.0+）',
    );
  }

  /// 分组选择弹窗：列出所有分组（勾选已加入的），可新建分组
  Future<void> _showFolderPicker(BangumiItem bangumiItem) async {
    final folders = CollectFolderService.loadAll();
    if (folders.isEmpty) {
      final name = await _showCreateFolderDialog();
      if (name == null || name.isEmpty) return;
      await CollectFolderService.createFolder(name);
      if (!mounted) return;
      await CollectFolderService.addToFolder(name, bangumiItem.id);
      KazumiDialog.showToast(message: '✅ 已加入分组「$name」');
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('加入分组',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final name in folders.keys)
              ListTile(
                leading: Icon(
                  CollectFolderService.isInFolder(name, bangumiItem.id)
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(name),
                trailing: Text(
                  '${folders[name]?.length ?? 0} 部',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
                onTap: () => Navigator.pop(context, name),
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded),
              title: const Text('新建分组'),
              onTap: () => Navigator.pop(context, '__create__'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == '__create__') {
      final name = await _showCreateFolderDialog();
      if (name == null || name.isEmpty) return;
      await CollectFolderService.createFolder(name);
      if (!mounted) return;
      await CollectFolderService.addToFolder(name, bangumiItem.id);
      KazumiDialog.showToast(message: '✅ 已加入分组「$name」');
      return;
    }
    final inFolder = CollectFolderService.isInFolder(selected, bangumiItem.id);
    if (inFolder) {
      await CollectFolderService.removeFromFolder(selected, bangumiItem.id);
      if (mounted) KazumiDialog.showToast(message: '已移出分组「$selected」');
    } else {
      await CollectFolderService.addToFolder(selected, bangumiItem.id);
      if (mounted) KazumiDialog.showToast(message: '✅ 已加入分组「$selected」');
    }
  }

  Future<String?> _showCreateFolderDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '如：待补番 / 二刷'),
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

  Future<void> _runFullSync({
    required CollectSyncPlan plan,
  }) async {
    final progressDialogKey = GlobalKey<_FullSyncProgressDialogState>();

    _showFullSyncProgressDialog(
      progressDialogKey: progressDialogKey,
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    bool webDavSynced = false;
    bool bangumiSynced = false;
    bool webDavUploaded = false;
    bool kazumiSynced = false;

    try {
      // 同步顺序：Bangumi(拉) → WebDAV(合并) → 樱花(先拉后传差异) → WebDAV(回传)
      // Bangumi 作为数据主源，先拉取合并到本地，再推送到其他后端
      
      // 1️⃣ 先拉取 Bangumi（如果有的话）
      if (plan.shouldSyncBangumi) {
        bangumiSynced = await _syncBangumiWithProgress(
          progressDialogKey: progressDialogKey,
        );
      }

      // 2️⃣ 再同步 WebDAV（如果有的话），双向合并
      if (plan.shouldSyncWebDavCollectibles) {
        progressDialogKey.currentState?.update('正在同步 WebDav 收藏...', null);
        webDavSynced =
            await collectController.syncCollectibles(showSuccessToast: false);
      }

      // 3️⃣ 樱花同步（统一走 KazumiSyncService：上传全量+删除标记 → 下载缺失，修复状态变更/删除不同步）
      if (plan.shouldSyncKazumi) {
        progressDialogKey.currentState?.update('正在同步樱花服务器收藏...', null);
        final kazumiMsg = await KazumiSyncService.syncCollect();
        kazumiSynced = !kazumiMsg.startsWith('❌');
        progressDialogKey.currentState?.update(kazumiMsg, null);
        collectController.loadCollectibles(); // 刷新列表
      }

      // 4️⃣ 如果 Bangumi 和 WebDAV 都开了，把 Bangumi 合并后的结果回传 WebDAV
      if (plan.shouldUploadWebDavAfterBangumi(
        webDavSynced: webDavSynced,
        bangumiSynced: bangumiSynced,
      )) {
        progressDialogKey.currentState?.update('正在回传最新收藏到 WebDav...', null);
        webDavUploaded = await collectController.uploadCollectiblesToWebDav(
          showSuccessToast: false,
        );
      }
    } finally {
      if (KazumiDialog.observer.hasKazumiDialog) {
        KazumiDialog.dismiss();
      }
    }

    KazumiDialog.showToast(
      message: _buildFullSyncSummary(
        plan: plan,
        webDavSynced: webDavSynced,
        bangumiSynced: bangumiSynced,
        webDavUploaded: webDavUploaded,
        kazumiSynced: kazumiSynced,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    collectController.loadCollectibles();
    tabController = TabController(vsync: this, length: tabs.length);
  }

  @override
  void dispose() {
    tabController?.dispose();
    super.dispose();
  }

  final List<Tab> tabs = const <Tab>[
    Tab(text: '在看'),
    Tab(text: '想看'),
    Tab(text: '搁置'),
    Tab(text: '看过'),
    Tab(text: '抛弃'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 104,
        bottom: TabBar(
          controller: tabController,
          tabs: tabs,
          indicatorColor: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('追番'),
        actions: [
          IconButton(
            tooltip: '追番日历',
            onPressed: () {
              final navContext = rootNavigatorKey.currentContext;
              if (navContext == null || !navContext.mounted) return;
              Navigator.of(navContext).push(
                MaterialPageRoute(builder: (_) => const CollectCalendarPage()),
              );
            },
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: '收藏分组',
            onPressed: () async {
              final navContext = rootNavigatorKey.currentContext;
              if (navContext == null || !navContext.mounted) return;
              await Navigator.of(navContext).push(
                MaterialPageRoute(builder: (_) => const CollectFolderPage()),
              );
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.folder_outlined),
          ),
          IconButton(
              onPressed: () {
                setState(() {
                  showDelete = !showDelete;
                });
              },
              icon: showDelete
                  ? const Icon(Icons.edit_outlined)
                  : const Icon(Icons.edit))
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          bool webDavenable =
              await GStorage.getSetting(SettingsKeys.webDavEnable);
          bool webDavCollectEnable =
              GStorage.getSetting(SettingsKeys.webDavEnableCollect);
          bool bgmSyncEnable =
              GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
          final syncPlan = CollectSyncPlan(
            webDavEnabled: webDavenable,
            webDavCollectiblesEnabled: webDavCollectEnable,
            bangumiEnabled: bgmSyncEnable,
            kazumiSyncEnabled: GStorage.getSetting(SettingsKeys.kazumiSyncEnable),
          );
          if (!syncPlan.canSync) {
            KazumiDialog.showToast(message: '同步功能不可用，请至少开启一个同步功能');
            return;
          }
          if (showDelete) {
            KazumiDialog.showToast(message: '编辑模式无法执行同步');
            return;
          }
          if (syncCollectiblesing) {
            return;
          }
          setState(() {
            syncCollectiblesing = true;
          });
          try {
            await _runFullSync(
              plan: syncPlan,
            );
          } finally {
            if (mounted) {
              setState(() {
                syncCollectiblesing = false;
              });
            }
          }
        },
        child: syncCollectiblesing
            ? const SizedBox(
                width: 32, height: 32, child: CircularProgressIndicator())
            : const Icon(Icons.sync_rounded),
      ),
      body: Observer(builder: (context) {
        return renderBody;
      }),
    );
  }

  Widget get renderBody {
    if (collectController.collectibles.isNotEmpty) {
      return Column(
        children: [
          _buildFolderFilterBar(),
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: contentGrid(collectController.collectibles),
            ),
          ),
        ],
      );
    } else {
      return const Center(
        child: GeneralEmptyState(
          icon: Icons.favorite_border_rounded,
          title: '暂无追番内容',
        ),
      );
    }
  }

  /// 顶部横向分组筛选 chips（"全部" + 各分组）
  Widget _buildFolderFilterBar() {
    final folders = CollectFolderService.loadAll();
    if (folders.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: const Text('全部'),
              selected: _activeFolder == null,
              onSelected: (_) => setState(() => _activeFolder = null),
            ),
          ),
          for (final name in folders.keys)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text('$name（${folders[name]?.length ?? 0}）'),
                selected: _activeFolder == name,
                onSelected: (_) => setState(() => _activeFolder = name),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> contentGrid(List<CollectedBangumi> collectedBangumiList) {
    // ⭐ 分组筛选：选中某个分组时只显示该分组内的番剧
    if (_activeFolder != null) {
      final folderIds = CollectFolderService.idsInFolder(_activeFolder!);
      collectedBangumiList = collectedBangumiList
          .where((c) => folderIds.contains(c.bangumiItem.id))
          .toList();
    }
    final bool showAnimeCounter =
        GStorage.getSetting(SettingsKeys.showAnimeCounter);
    List<Widget> gridViewList = [];
    List<List<CollectedBangumi>> collectedBangumiRenderItemList =
        List.generate(tabs.length, (_) => <CollectedBangumi>[]);
    for (CollectedBangumi element in collectedBangumiList) {
      collectedBangumiRenderItemList[element.type - 1].add(element);
    }
    for (List<CollectedBangumi> list in collectedBangumiRenderItemList) {
      list.sort((a, b) => b.time.millisecondsSinceEpoch
          .compareTo(a.time.millisecondsSinceEpoch));
    }
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    for (List<CollectedBangumi> collectedBangumiRenderItem
        in collectedBangumiRenderItemList) {
      gridViewList.add(
        CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(StyleString.cardSpace,
                  StyleString.cardSpace, StyleString.cardSpace, 0),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  mainAxisSpacing: StyleString.cardSpace - 2,
                  crossAxisSpacing: StyleString.cardSpace,
                  crossAxisCount: crossCount,
                  mainAxisExtent:
                      MediaQuery.of(context).size.width / crossCount / 0.65 +
                          MediaQuery.textScalerOf(context).scale(32.0),
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    return collectedBangumiRenderItem.isNotEmpty
                        ? Stack(
                            children: [
                              BangumiCardV(
                                bangumiItem: collectedBangumiRenderItem[index]
                                    .bangumiItem,
                                canTap: !showDelete,
                                onLongPress: () => _showShortcutMenu(
                                    collectedBangumiRenderItem[index]
                                        .bangumiItem),
                              ),
                              Positioned(
                                right: 5,
                                bottom: 5,
                                child: showDelete
                                    ? Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .secondaryContainer,
                                          shape: BoxShape.circle,
                                        ),
                                        child: CollectButton(
                                          bangumiItem:
                                              collectedBangumiRenderItem[index]
                                                  .bangumiItem,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSecondaryContainer,
                                        ),
                                      )
                                    : Container(),
                              ),
                            ],
                          )
                        : null;
                  },
                  childCount: collectedBangumiRenderItem.isNotEmpty
                      ? collectedBangumiRenderItem.length
                      : 10,
                ),
              ),
            ),
            if (collectedBangumiRenderItem.isNotEmpty && showAnimeCounter)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 12),
                      child: Text(
                        '总计：${collectedBangumiRenderItem.length}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return gridViewList;
  }
}

class _SyncStepStatus {
  const _SyncStepStatus(this.label, this.icon, this.color, this.progress);
  final String label;
  final IconData icon;
  final Color color;
  final double? progress;
}

class _FullSyncProgressDialog extends StatefulWidget {
  const _FullSyncProgressDialog({super.key});

  @override
  State<_FullSyncProgressDialog> createState() =>
      _FullSyncProgressDialogState();
}

class _FullSyncProgressDialogState extends State<_FullSyncProgressDialog> {
  final List<_SyncStepStatus> _steps = [
    const _SyncStepStatus('等待同步', Icons.circle_outlined, Color(0xFFBDBDBD), null),
    const _SyncStepStatus('等待同步', Icons.circle_outlined, Color(0xFFBDBDBD), null),
    const _SyncStepStatus('等待同步', Icons.circle_outlined, Color(0xFFBDBDBD), null),
  ];

  static const _stepLabels = ['Bangumi', 'WebDAV', '樱花服务器'];
  static const _stepColors = [0xFF6C5CE7, 0xFF3498DB, 0xFFE67E22];

  void update(String text, double? value) {
    if (!mounted) return;
    setState(() {
      // 根据 text 判断当前在同步哪个
      int stepIndex = -1;
      if (text.contains('Bangumi') || text.contains('bangumi')) stepIndex = 0;
      else if (text.contains('WebDav') || text.contains('WEBDAV')) stepIndex = 1;
      else if (text.contains('樱花') || text.contains('Kazumi')) stepIndex = 2;
      else if (text.contains('回传')) stepIndex = 1;

      // 标记之前的步骤为完成
      for (int i = 0; i < stepIndex; i++) {
        _steps[i] = _SyncStepStatus(
          '已完成', Icons.check_circle, Colors.green, 1.0,
        );
      }

      // 标记当前步骤
      if (stepIndex >= 0 && stepIndex < 3) {
        final isError = text.contains('❌');
        _steps[stepIndex] = _SyncStepStatus(
          isError ? text.replaceAll('❌ ', '') : text,
          isError ? Icons.error : Icons.sync,
          isError ? Colors.red : Color(_stepColors[stepIndex]),
          value,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sync, size: 20),
                    const SizedBox(width: 8),
                    const Text('全量同步', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...List.generate(3, (i) {
                  final step = _steps[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(step.icon, size: 20, color: step.color),
                        const SizedBox(width: 10),
                        Text(_stepLabels[i], style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            step.label,
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (step.progress != null)
                          SizedBox(
                            width: 40,
                            child: LinearProgressIndicator(
                              value: step.progress,
                              backgroundColor: colorScheme.surfaceContainerHighest,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
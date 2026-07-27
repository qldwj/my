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
import 'package:kazumi/modules/collect/collect_sync_plan.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';

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

      // 3️⃣ 樱花同步：先拉取云端数据，合并到本地，再上传本地差异（增量）
      if (plan.shouldSyncKazumi) {
        progressDialogKey.currentState?.update('正在拉取樱花服务器收藏...', null);
        try {
          // ✅ 使用只读接口 getRemoteCollect()
          final remoteRes = await AuthService.getRemoteCollect(); 
          if (remoteRes['error'] != null) {
            progressDialogKey.currentState?.update('❌ 拉取云端失败: ${remoteRes['error']}', null);
          } else {
            // 解析云端列表（新接口返回直接是 collect 数组，兼容旧格式）
            List remoteList = [];
            if (remoteRes['collect'] is List) {
              remoteList = remoteRes['collect'] as List;
            } else if (remoteRes['sync_data'] is Map && remoteRes['sync_data']['collect'] is List) {
              remoteList = remoteRes['sync_data']['collect'] as List;
            }
            // 下载本地缺失的条目
            int downloadCount = 0;
            final localIds = collectController.collectibles.map((c) => c.bangumiItem.id).toSet();
            for (final item in remoteList) {
              if (item is! Map) continue;
              final remoteId = item['id'];
              if (remoteId is! int) continue;
              if (!localIds.contains(remoteId)) {
                // 添加条目
                final bangumiItem = BangumiItem(
                  id: remoteId,
                  type: 0,
                  name: item['name']?.toString() ?? '未知',
                  nameCn: item['name_cn']?.toString() ?? '',
                  summary: item['summary']?.toString() ?? '',
                  airDate: item['air_date']?.toString() ?? '',
                  airWeekday: 0,
                  rank: 0,
                  images: {'large': item['image']?.toString() ?? ''},
                  tags: [],
                  alias: [],
                  ratingScore: (item['rating'] as num?)?.toDouble() ?? 0.0,
                  votes: 0,
                  votesCount: [],
                  info: '',
                );
                await GStorage.putCollectible(
                  CollectedBangumi(bangumiItem, DateTime.now(), item['type'] is int ? item['type'] : 1),
                );
                downloadCount++;
              }
            }
            if (downloadCount > 0) {
              collectController.loadCollectibles(); // 刷新列表
            }
            // 计算本地多余条目（本地有，云端没有）
            final remoteIds = remoteList.map((e) => (e as Map)['id'] as int).toSet();
            final localCollectAfter = collectController.collectibles; // 此时已经更新
            final diffList = localCollectAfter
                .where((c) => !remoteIds.contains(c.bangumiItem.id))
                .map((c) => {
                      'id': c.bangumiItem.id,
                      'name': c.bangumiItem.name,
                      'name_cn': c.bangumiItem.nameCn,
                      'type': c.type,
                      'time': c.time.toIso8601String(),
                      'image': c.bangumiItem.images['large'] ?? '',
                      'summary': c.bangumiItem.summary,
                      'rating': c.bangumiItem.ratingScore,
                    })
                .toList();

            int uploadCount = 0;
            if (diffList.isNotEmpty) {
              progressDialogKey.currentState?.update('正在上传新增条目到樱花服务器...', null);
              final uploadRes = await AuthService.syncData({'collect': diffList});
              if (uploadRes['error'] != null) {
                progressDialogKey.currentState?.update('❌ 上传失败: ${uploadRes['error']}', null);
              } else {
                uploadCount = diffList.length;
                kazumiSynced = true;
              }
            } else {
              kazumiSynced = true; // 没有差异也算成功
            }
            progressDialogKey.currentState?.update(
              '樱花同步完成 ✅ 下载 $downloadCount 项，上传 $uploadCount 项',
              null,
            );
          }
        } catch (e) {
          KazumiLogger().w('Kazumi sync failed', error: e);
          progressDialogKey.currentState?.update('❌ 樱花同步异常: $e', null);
        }
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
      return TabBarView(
        controller: tabController,
        children: contentGrid(collectController.collectibles),
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

  List<Widget> contentGrid(List<CollectedBangumi> collectedBangumiList) {
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
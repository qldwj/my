import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/sync_priority.dart';
import 'package:kazumi/modules/collect/collect_sync_plan.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/collect/collect_library_view.dart';
import 'package:kazumi/pages/collect/collect_sync_dialog.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 追番页（收藏）
///
/// 采用官方 Kazumi 的布局：AppBar「追番」+ 右上「同步」按钮，
/// 主体是 CollectLibraryView —— 分类横条 + 左右滑动切分类 + 网格卡片 +
/// 卡片内状态菜单 + 收藏内搜索。
class CollectPage extends StatefulWidget {
  const CollectPage({
    super.key,
    required this.controller,
  });

  final CollectController controller;

  @override
  State<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<CollectPage> {
  CollectController get collectController => widget.controller;

  bool _syncing = false;
  final Set<int> _pendingIds = {};

  bool get _busy => _syncing || _pendingIds.isNotEmpty;

  /// 同步三步（WebDAV 拉取 / Bangumi 拉取 / WebDAV 回传）
  /// 适配本仓库 CollectController 的方法签名（无 onError 参数，靠返回值+try）。
  Future<bool> _syncStep(
    CollectSyncStep step, {
    required ValueChanged<String> onError,
    required void Function(String message, int current, int total) onProgress,
  }) async {
    try {
      switch (step) {
        case CollectSyncStep.webDav:
          final ok = await collectController.syncCollectibles(
              showSuccessToast: false);
          if (!ok) onError('WebDAV 收藏同步失败');
          return ok;
        case CollectSyncStep.bangumi:
          final ok = await collectController.syncCollectiblesBangumi(
              showSuccessToast: false, onProgress: onProgress);
          if (!ok) onError('Bangumi 状态同步失败');
          return ok;
        case CollectSyncStep.upload:
          final ok = await collectController.uploadCollectiblesToWebDav(
              showSuccessToast: false);
          if (!ok) onError('回传 WebDAV 失败');
          return ok;
      }
    } catch (e) {
      onError('同步异常：$e');
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    collectController.loadCollectibles();
  }

  /// 修改收藏状态（卡片菜单触发）
  Future<void> _changeType(BangumiItem item, CollectType type) async {
    if (_busy || _pendingIds.contains(item.id)) return;
    setState(() => _pendingIds.add(item.id));
    try {
      if (type == CollectType.none) {
        await collectController.deleteCollect(item);
      } else {
        await collectController.addCollect(item, type: type.value);
      }
    } catch (_) {
      if (mounted) {
        KazumiDialog.showToast(message: '修改收藏状态失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _pendingIds.remove(item.id));
    }
  }

  /// 打开同步弹窗；未配置的服务会引导去对应设置页
  Future<void> _sync() async {
    if (_busy) return;
    setState(() => _syncing = true);
    try {
      final plan = CollectSyncPlan(
        webDavEnabled: GStorage.getSetting(SettingsKeys.webDavEnable),
        webDavCollectiblesEnabled:
            GStorage.getSetting(SettingsKeys.webDavEnableCollect),
        bangumiEnabled: GStorage.getSetting(SettingsKeys.bangumiSyncEnable),
      );
      final destination = await showDialog<CollectSyncDestination>(
        context: context,
        builder: (_) => CollectSyncDialog(
          plan: plan,
          priority: BangumiSyncPriority.fromValue(
            GStorage.getSetting(SettingsKeys.bangumiSyncPriority),
          ),
          onSync: _syncStep,
        ),
      );
      if (destination == null || !mounted) return;
      if (destination == CollectSyncDestination.webDavSettings) {
        context.pushNamed('/settings/webdav/');
      } else if (destination == CollectSyncDestination.bangumiSettings) {
        context.pushNamed('/settings/sync/bangumi');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 72,
        title: Text(
          '追番',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: '同步收藏',
              child: StateActionButton.tonal(
                text: '同步',
                onPressed: _busy ? null : _sync,
                icon: Icons.sync_rounded,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Observer(
          builder: (context) => CollectLibraryView(
            entries: collectController.collectibles.toList(),
            showRating: GStorage.getSetting(SettingsKeys.showRating),
            canEdit: (item) => !_busy && !_pendingIds.contains(item.id),
            onOpen: (item) => context.pushNamed('/info/', arguments: item),
            onChangeType: (item, type) => unawaited(_changeType(item, type)),
          ),
        ),
      ),
    );
  }
}

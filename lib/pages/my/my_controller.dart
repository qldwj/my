import 'dart:async';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/modules/my/watch_stats.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:mobx/mobx.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/update/auto_updater.dart';
// 引入公告服务
import 'package:yhdm/services/announcement/announcement_service.dart';
// 🆕 弹幕屏蔽词云端同步（恢复官方 2.3.3）
import 'package:yhdm/modules/danmaku/danmaku_shield_rule.dart';
import 'package:yhdm/repositories/danmaku_shield_repository.dart';
// 官方 2.3.7：我的页面观看统计（响应式监听历史/下载仓库）
import 'package:yhdm/repositories/download_repository.dart';
import 'package:yhdm/repositories/history_repository.dart';

part 'my_controller.g.dart';

class MyController = _MyController with _$MyController;

abstract class _MyController with Store {
  _MyController(
    this._historyRepository,
    this._downloadRepository,
    this._shieldRepository,
  );

  final IHistoryRepository _historyRepository;
  final IDownloadRepository _downloadRepository;
  final IDanmakuShieldRepository _shieldRepository;

  @observable
  WatchStats watchStats = const WatchStats();

  static const Duration _refreshDebounce = Duration(milliseconds: 300);

  int _viewerCount = 0;
  final List<StreamSubscription<void>> _subscriptions = [];
  Timer? _refreshDebounceTimer;

  // Route swaps can briefly attach two page instances.
  void attach() {
    _viewerCount++;
    if (_subscriptions.isEmpty) {
      for (final changes in [
        _historyRepository.changes,
        _downloadRepository.changes,
      ]) {
        _subscriptions.add(changes.listen((_) => _scheduleRefresh()));
      }
    }
    _refresh();
  }

  void detach() {
    if (--_viewerCount > 0) {
      return;
    }
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = null;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _scheduleRefresh() {
    // Coalesce frequent playback history writes.
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(_refreshDebounce, _refresh);
  }

  @action
  void _refresh() {
    watchStats = WatchStats.from(
      histories: _historyRepository.getAllHistories(),
      downloadRecords: _downloadRepository.getAllRecords(),
    );
  }

  @observable
  ObservableList<String> shieldList = ObservableList.of([]);

  StreamSubscription<DanmakuShieldChange>? _shieldSubscription;

  bool isDanmakuBlocked(String? danmaku) {
    if (danmaku == null || danmaku.isEmpty) return false;
    for (String item in shieldList) {
      if (item.isEmpty) continue;
      if (item.startsWith('/') && item.endsWith('/')) {
        if (item.length <= 2) continue;
        String pattern = item.substring(1, item.length - 1);
        try {
          if (RegExp(pattern).hasMatch(danmaku)) return true;
        } catch (_) {
          KazumiLogger()
              .e('Danmaku: invalid danmaku shield regex pattern: $pattern');
          continue;
        }
      } else {
        if (danmaku.contains(item)) return true;
      }
    }
    return false;
  }

  /// 🆕 云端同步版：监听仓库变更 + 初始化同步状态
  Future<void> loadShieldList() async {
    // Keep this subscription alive during playback.
    _shieldSubscription ??=
        _shieldRepository.changes.listen((_) => _refreshShieldList());
    _refreshShieldList();
    try {
      await _shieldRepository.initialize();
    } catch (e) {
      KazumiLogger()
          .e('Danmaku: failed to initialize shield sync state', error: e);
    }
  }

  void _refreshShieldList() {
    runInAction(() {
      shieldList
        ..clear()
        ..addAll(_shieldRepository.getRules());
    });
  }

  Future<bool> addShieldList(String item) async {
    final error = DanmakuShieldRule.validate(item);
    if (error != null) {
      KazumiDialog.showToast(
          message: switch (error) {
        DanmakuShieldRuleError.empty => '请输入关键词',
        DanmakuShieldRuleError.tooLong => '关键词过长',
      });
      return false;
    }
    return _saveShieldRule(item, deleted: false);
  }

  Future<bool> removeShieldList(String item) =>
      _saveShieldRule(item, deleted: true);

  Future<bool> _saveShieldRule(String item, {required bool deleted}) async {
    try {
      final changed = await _shieldRepository.setRule(item, deleted: deleted);
      if (!changed && !deleted) {
        KazumiDialog.showToast(message: '已存在该关键词');
        return false;
      }
      return true;
    } catch (e) {
      KazumiLogger().e('Danmaku: failed to save shield rule', error: e);
      KazumiDialog.showToast(message: '屏蔽规则保存失败，请重试');
      return false;
    }
  }

  Future<bool> checkUpdate({String type = 'manual'}) async {
    try {
      final autoUpdater = AutoUpdater();

      if (type == 'manual') {
        await autoUpdater.manualCheckForUpdates();
      } else {
        // 自动检查更新（autoCheckForUpdates 内部已经负责处理 pending 安装
        // 提示，所以这里不再额外调 checkPendingUpdate，避免双弹"立即安装"
        // 对话框 —— 用户反馈"出现两个对话框/关掉一个又弹一个"的根因）。
        await autoUpdater.autoCheckForUpdates();
        // 自动检查活动（仅在自动检查时触发，接口复用原公告接口）
        await AnnouncementService.checkAnnouncement();
      }

      return true;
    } catch (err) {
      KazumiLogger().e('Update: check update failed', error: err);
      if (type == 'manual') {
        KazumiDialog.showToast(message: '检查更新失败，请稍后重试');
      }
      return false;
    }
  }
}
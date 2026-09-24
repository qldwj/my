import 'dart:async';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/update/auto_updater.dart';
// 引入公告服务
import 'package:kazumi/services/announcement/announcement_service.dart';
// 🆕 弹幕屏蔽词云端同步（恢复官方 2.3.3）
import 'package:kazumi/modules/danmaku/danmaku_shield_rule.dart';
import 'package:kazumi/repositories/danmaku_shield_repository.dart';

part 'my_controller.g.dart';

class MyController = _MyController with _$MyController;

abstract class _MyController with Store {
  _MyController(this._shieldRepository);

  final IDanmakuShieldRepository _shieldRepository;

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
        // 自动检查更新
        await autoUpdater.autoCheckForUpdates();
        // 检查是否有待安装的更新（静默下载的）
        await autoUpdater.checkPendingUpdate();
        // 自动检查公告（仅在自动检查时触发）
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
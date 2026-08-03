import 'dart:async';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 樱花动漫 云同步服务
///
/// 提供：
/// - [syncCollect]：收藏双向同步（下载云端缺失 + 上传本地差异）
/// - [startAutoSync] / [stopAutoSync]：登录后每 30 分钟自动同步（默认开启）
class KazumiSyncService {
  KazumiSyncService._();

  static Timer? _autoSyncTimer;

  /// 同步间隔（默认 30 分钟）
  static const Duration _interval = Duration(minutes: 30);

  /// 收藏双向同步。返回结果消息（成功以 ✅ 开头，失败以 ❌ 开头）。
  static Future<String> syncCollect() async {
    final token = AuthService.getLocalToken();
    if (token == null || token.isEmpty) {
      return '❌ 未登录';
    }
    try {
      final remoteRes = await AuthService.getRemoteCollect();
      if (remoteRes['error'] != null) {
        return '❌ 获取云端数据失败: ${remoteRes['error']}';
      }

      List<dynamic> remoteList = [];
      if (remoteRes['collect'] is List) {
        remoteList = remoteRes['collect'] as List;
      } else {
        if (remoteRes['sync_data'] is Map &&
            remoteRes['sync_data']['collect'] is List) {
          remoteList = remoteRes['sync_data']['collect'] as List;
        } else {
          remoteList = [];
        }
      }

      int downloadCount = 0;
      final localCollectBefore = GStorage.collectibles.values.toList();
      final localIds = localCollectBefore.map((c) => c.bangumiItem.id).toSet();

      for (final item in remoteList) {
        if (item is! Map) continue;
        final remoteId = item['id'];
        if (remoteId is! int) continue;
        if (!localIds.contains(remoteId)) {
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
            CollectedBangumi(
              bangumiItem,
              DateTime.now(),
              item['type'] is int ? item['type'] as int : 1,
            ),
          );
          downloadCount++;
        }
      }

      final localCollectAfter = GStorage.collectibles.values.toList();
      final remoteIds =
          remoteList.map((e) => (e as Map)['id'] as int).toSet();

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
        final uploadRes = await AuthService.syncData({'collect': diffList});
        if (uploadRes['error'] != null) {
          return '❌ 上传差异失败: ${uploadRes['error']}';
        }
        uploadCount = diffList.length;
      }

      return '✅ 同步完成 下载 $downloadCount 项，上传 $uploadCount 项';
    } catch (e, st) {
      KazumiLogger().e('樱花同步失败', error: e, stackTrace: st);
      return '❌ 同步失败: $e';
    }
  }

  /// 启动自动同步（登录后每 30 分钟一次，默认开启）
  static void startAutoSync() {
    if (_autoSyncTimer != null) return;
    _autoSyncTimer = Timer.periodic(_interval, (_) async {
      try {
        if (!GStorage.getSetting(SettingsKeys.kazumiAutoSync)) return;
        if (!AuthService.isLoggedIn) return;
        final msg = await syncCollect();
        KazumiLogger().i('自动同步: $msg');
      } catch (e) {
        KazumiLogger().w('自动同步异常', error: e);
      }
    });
  }

  static void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }
}

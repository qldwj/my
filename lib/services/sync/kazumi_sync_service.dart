import 'dart:async';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/history_storage_coordinator.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 樱花动漫 云同步服务
///
/// 提供：
/// - [syncCollect]：收藏双向同步（下载云端缺失 + 上传本地差异）
/// - [syncHistory]：历史记录（含播放进度）双向同步
/// - [syncAll]：收藏 + 历史 + 进度 全量同步
/// - [startAutoSync] / [stopAutoSync]：登录后每 30 分钟自动同步（默认开启）
class KazumiSyncService {
  KazumiSyncService._();

  static Timer? _autoSyncTimer;

  /// 同步间隔（默认 30 分钟）
  static const Duration _interval = Duration(minutes: 30);

  /// 单次上传历史条数上限（控制请求体积）
  static const int _historyUploadLimit = 200;

  /// 收藏双向同步。返回结果消息（成功以 ✅ 开头，失败以 ❌ 开头）。
  ///
  /// 修复要点：
  /// - 状态变更（本地与云端都有同一条目但 type 不同）→ 上传覆盖，不再漏同步
  /// - 本地删除的条目 → 通过 removed 通知服务器删除，避免全量同步时被下载回来
  /// - 先上传再下载，保证删除/变更立即生效
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

      // ── 1. 本地与云端快照 ──
      final localCollect = GStorage.collectibles.values.toList();
      final localById = {
        for (final c in localCollect) c.bangumiItem.id: c,
      };
      final remoteIds = <int>{};
      for (final item in remoteList) {
        if (item is Map && item['id'] is int) {
          remoteIds.add(item['id'] as int);
        }
      }

      // ── 2. 上传：本地全量（覆盖新增 + 状态变更）+ removed（本地已删除）──
      final uploadItems = localCollect
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

      // 本地删除记录：每个 bangumiID 取最新一条 change，action==3 才算"确实删除了"
      final latestActionByBangumi = <int, int>{};
      for (final change in GStorage.collectChanges.values) {
        final existing = latestActionByBangumi[change.bangumiID];
        if (existing == null || change.timestamp >= existing) {
          latestActionByBangumi[change.bangumiID] = change.action;
        }
      }
      final deleteRecordedIds = latestActionByBangumi.entries
          .where((e) => e.value == 3)
          .map((e) => e.key)
          .toSet();

      // removed = 云端有 && 本地没有 && 本地有删除记录
      // ⚠️ 保护：本地收藏为空（新设备/被清空）时绝不传 removed，防止一次同步清空服务器
      final removedIds = localCollect.isEmpty
          ? <int>[]
          : remoteIds
              .where((id) =>
                  !localById.containsKey(id) && deleteRecordedIds.contains(id))
              .toList();

      int uploadCount = 0;
      if (uploadItems.isNotEmpty || removedIds.isNotEmpty) {
        final uploadRes = await AuthService.syncData({
          'items': uploadItems,
          'removed': removedIds,
        });
        if (uploadRes['error'] != null) {
          return '❌ 上传差异失败: ${uploadRes['error']}';
        }
        uploadCount = uploadItems.length + removedIds.length;
      }

      // ── 3. 下载：云端有、本地缺失（且非本次删除）→ 加入本地 ──
      int downloadCount = 0;
      for (final item in remoteList) {
        if (item is! Map) continue;
        final remoteId = item['id'];
        if (remoteId is! int) continue;
        if (removedIds.contains(remoteId)) continue; // 本次刚删除，跳过
        if (localById.containsKey(remoteId)) continue; // 本地已有，保留本地状态
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
          tags: const [],
          alias: const [],
          ratingScore: (item['rating'] as num?)?.toDouble() ?? 0.0,
          votes: 0,
          votesCount: const [],
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

      return '✅ 同步完成 上传 $uploadCount 项，下载 $downloadCount 项';
    } catch (e, st) {
      KazumiLogger().e('樱花同步失败', error: e, stackTrace: st);
      return '❌ 同步失败: $e';
    }
  }

  /// 历史记录（含播放进度）双向同步。
  /// 策略：上传本地最近 [ _historyUploadLimit] 条 → 拉取云端 → 按 key + lastWatchTime 合并。
  static Future<String> syncHistory() async {
    final token = AuthService.getLocalToken();
    if (token == null || token.isEmpty) {
      return '❌ 未登录';
    }
    try {
      // ── 1. 上传本地历史（按最近观看排序，取前 N 条控制体积）──
      final localItems = <Map<String, dynamic>>[];
      for (final h in GStorage.histories.values) {
        final progresses = <Map<String, dynamic>>[];
        h.progresses.forEach((ep, p) {
          progresses.add({
            'episode': p.episode,
            'road': p.road,
            'progressMs': p.progress.inMilliseconds,
            'updatedAtMs': p.updatedAtMs,
          });
        });
        localItems.add({
          'key': h.key,
          'id': h.bangumiItem.id,
          'name': h.bangumiItem.name,
          'name_cn': h.bangumiItem.nameCn,
          'image': h.bangumiItem.images['large'] ?? '',
          'summary': h.bangumiItem.summary,
          'rating': h.bangumiItem.ratingScore,
          'adapterName': h.adapterName,
          'lastWatchEpisode': h.lastWatchEpisode,
          'lastWatchEpisodeName': h.lastWatchEpisodeName,
          'progressMs':
              h.progresses[h.lastWatchEpisode]?.progress.inMilliseconds ?? 0,
          'lastSrc': h.lastSrc,
          'entryKind': h.entryKind,
          'episodePageUrl': h.episodePageUrl,
          'lastWatchTime': h.lastWatchTime.millisecondsSinceEpoch,
          'progresses': progresses,
        });
      }
      localItems.sort((a, b) =>
          (b['lastWatchTime'] as int).compareTo(a['lastWatchTime'] as int));
      final uploadItems = localItems.take(_historyUploadLimit).toList();

      final upRes = await AuthService.syncData(
        {'items': uploadItems},
        type: 'history',
      );
      if (upRes['error'] != null) {
        return '❌ 上传历史失败: ${upRes['error']}';
      }

      // ── 2. 拉取云端历史并合并到本地 ──
      final remoteRes = await AuthService.getRemoteSync();
      if (remoteRes['error'] != null) {
        return '❌ 拉取云端失败: ${remoteRes['error']}';
      }
      final remoteList = remoteRes['history'] is List
          ? remoteRes['history'] as List
          : const <dynamic>[];

      var merged = 0;
      await HistoryStorageCoordinator().run(() async {
        for (final raw in remoteList) {
          if (raw is! Map) continue;
          final remoteTime = (raw['lastWatchTime'] as num?)?.toInt() ?? 0;
          final adapterName = raw['adapterName']?.toString() ?? '';
          final entryKind = raw['entryKind']?.toString() ??
              HistoryEntryKind.online;
          final bangumiItem = BangumiItem(
            id: (raw['id'] as num?)?.toInt() ?? 0,
            type: 0,
            name: raw['name']?.toString() ?? '未知',
            nameCn: raw['name_cn']?.toString() ?? '',
            summary: raw['summary']?.toString() ?? '',
            airDate: '',
            airWeekday: 0,
            rank: 0,
            images: {'large': raw['image']?.toString() ?? ''},
            tags: const [],
            alias: const [],
            ratingScore: (raw['rating'] as num?)?.toDouble() ?? 0.0,
            votes: 0,
            votesCount: const [],
            info: '',
          );
          final key = History.getKey(adapterName, bangumiItem,
              entryKind: entryKind);
          final local = GStorage.histories.get(key);
          if (local != null &&
              local.lastWatchTime.millisecondsSinceEpoch >= remoteTime) {
            continue; // 本地更新，跳过
          }
          final history = History(
            bangumiItem,
            (raw['lastWatchEpisode'] as num?)?.toInt() ?? 0,
            adapterName,
            DateTime.fromMillisecondsSinceEpoch(remoteTime),
            raw['lastSrc']?.toString() ?? '',
            raw['lastWatchEpisodeName']?.toString() ?? '',
            entryKind: entryKind,
            episodePageUrl: raw['episodePageUrl']?.toString() ?? '',
          );
          final progs = raw['progresses'];
          if (progs is List) {
            for (final p in progs) {
              if (p is! Map) continue;
              final ep = (p['episode'] as num?)?.toInt() ?? 0;
              final road = (p['road'] as num?)?.toInt() ?? 0;
              final ms = (p['progressMs'] as num?)?.toInt() ?? 0;
              final upd = (p['updatedAtMs'] as num?)?.toInt() ?? 0;
              history.progresses[ep] = Progress(ep, road, ms, updatedAtMs: upd);
            }
          }
          await GStorage.histories.put(key, history);
          merged++;
        }
        await GStorage.histories.flush();
      });

      return '✅ 历史同步完成 上传 ${uploadItems.length} 条，合并 $merged 条';
    } catch (e, st) {
      KazumiLogger().e('历史云同步失败', error: e, stackTrace: st);
      return '❌ 历史同步失败: $e';
    }
  }

  /// 收藏 + 历史 全量同步。返回结果消息列表。
  static Future<List<String>> syncAll() async {
    final results = <String>[];
    results.add(await syncCollect());
    results.add(await syncHistory());
    return results;
  }

  /// 启动自动同步（登录后每 30 分钟一次，默认开启）
  static void startAutoSync() {
    if (_autoSyncTimer != null) return;
    _autoSyncTimer = Timer.periodic(_interval, (_) async {
      try {
        if (!GStorage.getSetting(SettingsKeys.kazumiAutoSync)) return;
        if (!AuthService.isLoggedIn) return;
        final msgs = await syncAll();
        for (final msg in msgs) {
          KazumiLogger().i('自动同步: $msg');
        }
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

// ignore_for_file: library_private_types_in_public_api

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'dart:async';

import 'package:yhdm/modules/danmaku/danmaku_module.dart';
import 'package:yhdm/pages/player/controller/player_models.dart';
import 'package:yhdm/pages/download/download_controller.dart';
import 'package:yhdm/request/apis/bangumi_api.dart';
import 'package:yhdm/request/apis/danmaku_api.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/player/danmaku_cache_service.dart';
import 'package:mobx/mobx.dart';
import 'package:yhdm/utils/danmaku.dart';

part 'player_danmaku_controller.g.dart';

class PlayerDanmakuController = _PlayerDanmakuController
    with _$PlayerDanmakuController;

enum DanmakuLoadStatus {
  success,
  empty,
  failed,
}

class DanmakuLoadResult {
  const DanmakuLoadResult({
    required this.danmakus,
    required this.bangumiID,
    required this.status,
  });

  factory DanmakuLoadResult.success({
    required List<DanmakuEntry> danmakus,
    required int bangumiID,
  }) {
    return DanmakuLoadResult(
      danmakus: danmakus,
      bangumiID: bangumiID,
      status: danmakus.isEmpty
          ? DanmakuLoadStatus.empty
          : DanmakuLoadStatus.success,
    );
  }

  factory DanmakuLoadResult.failed({
    required int bangumiID,
  }) {
    return DanmakuLoadResult(
      danmakus: const [],
      bangumiID: bangumiID,
      status: DanmakuLoadStatus.failed,
    );
  }

  final List<DanmakuEntry> danmakus;
  final int bangumiID;
  final DanmakuLoadStatus status;

  bool get hasDanmakus => status == DanmakuLoadStatus.success;

  bool get isFailed => status == DanmakuLoadStatus.failed;
}

class DanmakuTimeline {
  static int? resolveSourceSecond(
    Duration playbackPosition,
    double timelineOffsetSeconds,
  ) {
    final sourceMilliseconds = playbackPosition.inMilliseconds -
        (timelineOffsetSeconds * 1000).round();
    if (sourceMilliseconds < 0) {
      return null;
    }
    return Duration(milliseconds: sourceMilliseconds).inSeconds;
  }

  static int staggerDelayMilliseconds({
    required int index,
    required int total,
  }) {
    if (total <= 0) {
      return 0;
    }
    return index * 1000 ~/ total;
  }
}

abstract class _PlayerDanmakuController with Store {
  _PlayerDanmakuController({
    required this.isLocalPlayback,
    required this.downloadController,
  });

  final bool Function() isLocalPlayback;
  final DownloadController downloadController;

  late canvas.DanmakuController canvasController;

  final Map<int, List<DanmakuEntry>> danDanmakus = {};
  @observable
  bool danmakuOn = false;
  @observable
  bool danmakuLoading = false;
  DanmakuDestination danmakuDestination = DanmakuDestination.remoteDanmaku;

  int bangumiID = 0;
  int _scheduledDanmakuGeneration = 0;

  int get scheduledDanmakuGeneration => _scheduledDanmakuGeneration;

  double get timelineOffsetSeconds {
    final offset = GStorage.getSetting(SettingsKeys.danmakuTimeOffset);
    return offset;
  }

  int? resolveDanmakuSecond(Duration playbackPosition) {
    return DanmakuTimeline.resolveSourceSecond(
      playbackPosition,
      timelineOffsetSeconds,
    );
  }

  List<DanmakuEntry> danmakusForPlaybackPosition(Duration playbackPosition) {
    final danmakuSecond = resolveDanmakuSecond(playbackPosition);
    if (danmakuSecond == null) {
      return const [];
    }
    return danDanmakus[danmakuSecond] ?? const [];
  }

  @action
  void setDanmakuEnabled(bool value) {
    danmakuOn = value;
  }

  void clearAndInvalidateScheduledDanmakus() {
    _scheduledDanmakuGeneration++;
    canvasController.clear();
  }

  // Fetching must not mutate current danmaku state; VideoPageController applies
  // the result only after confirming the playback session is still current.
  Future<DanmakuLoadResult> fetchDanmaku(
    int bangumiId,
    String pluginName,
    int episode, {
    String bangumiName = '',
  }) async {
    if (isLocalPlayback()) {
      return await _fetchCachedDanmaku(
        bangumiId,
        pluginName,
        episode,
      );
    }
    // 🔴 四源并发拉取：弹弹play / B站 / Animeko（互不影响失败；自建独立补拉）
    final danDanFuture = _fetchDanDanmakuByBgmBangumiID(
      bangumiId,
      episode,
    );
    final animekoFuture = _fetchAnimekoDanmaku(
      bangumiId,
      episode,
    );
    final biliFuture = _fetchBiliDanmaku(
      bangumiId,
      bangumiName,
      episode,
    );
    final results = await Future.wait([danDanFuture, biliFuture, animekoFuture]);
    final danDanResult = results[0] as DanmakuLoadResult;
    final biliResult = results[1] as DanmakuLoadResult;
    final animekoResult = results[2] as DanmakuLoadResult;
    // 弹弹优先排最前，B站 / Animeko 合并补充
    final merged = <DanmakuEntry>[
      ...danDanResult.danmakus,
      ...biliResult.danmakus,
      ...animekoResult.danmakus,
    ];
    if (merged.isNotEmpty) {
      KazumiLogger().i(
          'PlayerController: 弹弹+B站+Animeko 拉取 ${merged.length} 条弹幕 (bangumiId=$bangumiId)');
      // 🆕 缓存到本地库（下次源挂了也能看）
      unawaited(DanmakuCacheService.save(
        bangumiId: bangumiId,
        episode: episode,
        danmakus: merged.map((e) => e.toJson()).toList(),
      ));
      return DanmakuLoadResult.success(
        danmakus: merged,
        bangumiID: danDanResult.bangumiID,
      );
    }

    // 🆕 弹弹+Animeko 都没弹幕 → 尝试本地缓存兜底
    final cached = await DanmakuCacheService.load(
      bangumiId: bangumiId,
      episode: episode,
    );
    if (cached != null && cached.isNotEmpty) {
      final entries = cached
          .whereType<Map>()
          .map((e) => DanmakuEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (entries.isNotEmpty) {
        KazumiLogger().i('PlayerController: 使用本地缓存弹幕 ${entries.length} 条');
        return DanmakuLoadResult.success(
          danmakus: entries,
          bangumiID: danDanResult.bangumiID,
        );
      }
    }

    // 都没有：返回失败（由上层提示）
    return DanmakuLoadResult.failed(bangumiID: danDanResult.bangumiID);
  }

  /// 通过 B站搜索拉取弹幕（真正的 B站直连源）
  Future<DanmakuLoadResult> _fetchBiliDanmaku(
      int bgmBangumiID, String bangumiName, int episode) async {
    try {
      // 🔴 先查众包共享后端（自己的 PHP）：输入 Bangumi ID 拿 cid，避免每次被 B站 412 卡搜索
      var cid = await DanmakuApi.queryBiliCidFromServer(bgmBangumiID, episode);
      var fromServer = cid > 0;
      // 未命中才自己搜索（番名 → bvid → cid）
      if (cid <= 0) {
        final videos = await DanmakuApi.searchBiliVideos(bangumiName);
        if (videos.isEmpty) {
          return DanmakuLoadResult.failed(bangumiID: bgmBangumiID);
        }
        final first = videos.first;
        cid = await DanmakuApi.getBiliCid(
          bvid: first['bvid']?.toString() ?? '',
          aid: (first['aid'] as num?)?.toInt() ?? 0,
          episode: episode,
        );
        if (cid > 0) {
          // 搜索成功 → 回传共享（别人也能用）
          unawaited(DanmakuApi.uploadBiliCidToServer(
            bgmBangumiID,
            episode,
            cid,
            title: bangumiName,
          ));
        }
      }
      if (cid <= 0) {
        return DanmakuLoadResult.failed(bangumiID: bgmBangumiID);
      }
      final danmakus = await DanmakuApi.getBiliDanmaku(cid);
      if (danmakus.isEmpty) {
        return DanmakuLoadResult.failed(bangumiID: bgmBangumiID);
      }
      KazumiLogger().i(
          'PlayerController: 从 B站拉取到 ${danmakus.length} 条弹幕 '
          '($bangumiName EP$episode${fromServer ? ", 来源:共享cid" : ""})');
      return DanmakuLoadResult.success(
        danmakus: danmakus,
        bangumiID: bgmBangumiID,
      );
    } catch (e) {
      KazumiLogger().w('PlayerController: B站弹幕拉取异常', error: e);
      return DanmakuLoadResult.failed(bangumiID: bgmBangumiID);
    }
  }

  @action
  void beginDanmakuLoad() {
    danDanmakus.clear();
    danmakuLoading = true;
  }

  @action
  void applyDanmakuLoad(
    DanmakuLoadResult result, {
    required bool enableDanmaku,
  }) {
    bangumiID = result.bangumiID;
    addDanmakus(result.danmakus);
    danmakuOn = enableDanmaku;
    danmakuLoading = false;
  }

  @action
  void applyUnavailableDanmakuLoad(DanmakuLoadResult result) {
    bangumiID = result.bangumiID;
    danDanmakus.clear();
    danmakuOn = false;
    danmakuLoading = false;
  }

  @action
  void finishDanmakuLoad({bool disableDanmaku = false}) {
    if (disableDanmaku) {
      danDanmakus.clear();
      danmakuOn = false;
    }
    danmakuLoading = false;
  }

  Future<DanmakuLoadResult> _fetchCachedDanmaku(
      int bangumiId, String pluginName, int episode) async {
    KazumiLogger().i(
        'PlayerController: attempting to load cached danmaku for episode $episode');
    var nextBangumiID = bangumiID;
    try {
      final cachedDanmakus = await downloadController.getCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
      );

      if (cachedDanmakus != null && cachedDanmakus.isNotEmpty) {
        KazumiLogger().i(
            'PlayerController: loaded ${cachedDanmakus.length} cached danmakus');
        return DanmakuLoadResult.success(
          danmakus: cachedDanmakus,
          bangumiID: nextBangumiID,
        );
      } else {
        KazumiLogger()
            .i('PlayerController: no cached danmaku, attempting online fetch');
        try {
          nextBangumiID =
              await DanmakuApi.getDanDanBangumiIDByBgmBangumiID(bangumiId);
          if (nextBangumiID != 0) {
            var res = await DanmakuApi.getDanDanmaku(nextBangumiID, episode);
            if (res.isNotEmpty) {
              KazumiLogger()
                  .i('PlayerController: fetched ${res.length} danmakus online');
              _saveDanmakuToCache(downloadController, bangumiId, pluginName,
                  episode, res, nextBangumiID);
            }
            return DanmakuLoadResult.success(
              danmakus: res,
              bangumiID: nextBangumiID,
            );
          }
        } catch (e) {
          KazumiLogger().w(
              'PlayerController: failed to fetch danmaku online (may be offline)',
              error: e);
          return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
        }
      }
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to load cached danmaku', error: e);
      return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
    }
    return DanmakuLoadResult.success(
      danmakus: const [],
      bangumiID: nextBangumiID,
    );
  }

  void _saveDanmakuToCache(
      DownloadController downloadController,
      int bangumiId,
      String pluginName,
      int episode,
      List<DanmakuEntry> danmakus,
      int danDanID) {
    try {
      downloadController.updateCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
        danmakus,
        danDanID,
      );
      KazumiLogger()
          .i('PlayerController: saved ${danmakus.length} danmakus to cache');
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to save danmaku to cache', error: e);
    }
  }

  Future<DanmakuLoadResult> _fetchDanDanmakuByBgmBangumiID(
      int bgmBangumiID, int episode) async {
    KazumiLogger().i(
        'PlayerController: attempting to get danmaku [BgmBangumiID] $bgmBangumiID');
    var nextBangumiID = bangumiID;
    try {
      nextBangumiID =
          await DanmakuApi.getDanDanBangumiIDByBgmBangumiID(bgmBangumiID);
      if (nextBangumiID == 0) {
        return DanmakuLoadResult.success(
          danmakus: const [],
          bangumiID: nextBangumiID,
        );
      }
      var res = await DanmakuApi.getDanDanmaku(nextBangumiID, episode);
      return DanmakuLoadResult.success(
        danmakus: res,
        bangumiID: nextBangumiID,
      );
    } catch (e) {
      KazumiLogger().w(
          'PlayerController: failed to get danmaku [BgmBangumiID] $bgmBangumiID',
          error: e);
    }
    return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
  }

  /// 🆕 Animeko 公益弹幕：先取 Bangumi 剧集 ID，再拉 Animeko 弹幕
  Future<DanmakuLoadResult> _fetchAnimekoDanmaku(
      int bgmBangumiID, int episode) async {
    try {
      final episodeInfo = await BangumiApi.getBangumiEpisodeByID(
          bgmBangumiID, episode);
      if (episodeInfo.id <= 0) {
        return DanmakuLoadResult.success(
            danmakus: const [], bangumiID: bgmBangumiID);
      }
      final res = await DanmakuApi.getAnimekoDanmaku(episodeInfo.id);
      return DanmakuLoadResult.success(
        danmakus: res,
        bangumiID: bgmBangumiID,
      );
    } catch (e) {
      KazumiLogger().w('PlayerController: Animeko 弹幕拉取失败', error: e);
      return DanmakuLoadResult.failed(bangumiID: bgmBangumiID);
    }
  }

  @action
  Future<bool> getDanDanmakuByEpisodeID(int episodeID) async {
    KazumiLogger().i('PlayerController: attempting to get danmaku $episodeID');
    danmakuLoading = true;
    try {
      danDanmakus.clear();
      var res = await DanmakuApi.getDanDanmakuByEpisodeID(episodeID);
      addDanmakus(res);
      return res.isNotEmpty;
    } catch (e) {
      KazumiLogger().w('PlayerController: failed to get danmaku', error: e);
      rethrow;
    } finally {
      danmakuLoading = false;
    }
  }

  void addDanmakus(List<DanmakuEntry> danmakus) {
    final bool danmakuDeduplicationEnable =
        GStorage.getSetting(SettingsKeys.danmakuDeduplication);

    final List<DanmakuEntry> listToAdd = danmakuDeduplicationEnable
        ? mergeDuplicateDanmakus(danmakus, timeWindowSeconds: 5)
        : danmakus;

    for (final element in listToAdd) {
      final danmakuSecond = element.time.toInt();
      (danDanmakus[danmakuSecond] ??= <DanmakuEntry>[]).add(element);
    }
  }

  void updateDanmakuSpeed(double playerSpeed) {
    final baseDuration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    final followSpeed = GStorage.getSetting(SettingsKeys.danmakuFollowSpeed);

    final duration = followSpeed ? (baseDuration / playerSpeed) : baseDuration;
    canvasController
        .updateOption(canvasController.option.copyWith(duration: duration));
  }
}

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
  Future<DanmakuLoadResult>? _danDanPrefetch;
  int _danDanPrefetchKey = -1;

  /// 弹弹play 预取：在视频解析/缓冲阶段就先发起，先于其他来源。
  Future<DanmakuLoadResult> prefetchDanDan(int bangumiId, int episode) {
    final key = bangumiId * 100000 + episode;
    if (_danDanPrefetch == null || _danDanPrefetchKey != key) {
      _danDanPrefetchKey = key;
      _danDanPrefetch = _fetchDanDanmakuByBgmBangumiID(bangumiId, episode);
    }
    return _danDanPrefetch!;
  }

  Future<DanmakuLoadResult> fetchDanmaku(
    int bangumiId,
    String pluginName,
    int episode,
  ) async {
    if (isLocalPlayback()) {
      return await _fetchCachedDanmaku(
        bangumiId,
        pluginName,
        episode,
      );
    }
    // 🔴 弹弹play 优先：先出弹幕，其余来源后台补，不拖慢首屏。
    final danDanResult = await prefetchDanDan(bangumiId, episode);
    if (danDanResult.hasDanmakus) {
      unawaited(_appendOtherSources(bangumiId, episode));
      unawaited(DanmakuCacheService.save(
        bangumiId: bangumiId,
        episode: episode,
        danmakus: danDanResult.danmakus.map((e) => e.toJson()).toList(),
      ));
      return danDanResult;
    }
    // 弹弹play 无结果：再等其余来源，避免误判"无弹幕"
    final other = await _fetchOtherSources(bangumiId, episode);
    final merged = <DanmakuEntry>[
      ...danDanResult.danmakus,
      ...other.danmakus,
    ];
    if (merged.isNotEmpty) {
      KazumiLogger().i(
          'PlayerController: 弹弹+其余来源拉取 ${merged.length} 条弹幕 (bangumiId=$bangumiId)');
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

    // 🆕 弹弹+其余都没弹幕 → 尝试本地缓存兜底
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

  /// 其余来源（Animeko 等）；失败静默，不影响弹弹play。
  Future<DanmakuLoadResult> _fetchOtherSources(
      int bangumiId, int episode) async {
    final results = await Future.wait([
      _fetchAnimekoDanmaku(bangumiId, episode),
    ]);
    final animekoResult = results[0] as DanmakuLoadResult;
    return DanmakuLoadResult.success(
      danmakus: animekoResult.danmakus,
      bangumiID: animekoResult.bangumiID,
    );
  }

  /// 弹弹play 已有结果时，其余来源后台补齐（追加到已显示的弹幕上）。
  Future<void> _appendOtherSources(int bangumiId, int episode) async {
    try {
      final other = await _fetchOtherSources(bangumiId, episode);
      if (other.hasDanmakus) {
        addDanmakus(other.danmakus);
      }
    } catch (e) {
      KazumiLogger().w('PlayerController: 补充其他来源弹幕失败', error: e);
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

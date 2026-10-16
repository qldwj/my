import 'dart:async';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/modules/roads/road_module.dart';
import 'package:yhdm/pages/video/video_playback_args.dart';
import 'package:yhdm/plugins/plugins.dart';
import 'package:yhdm/pages/history/history_controller.dart';
import 'package:yhdm/pages/player/player_controller.dart';
import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/modules/download/download_module.dart';
import 'package:yhdm/modules/history/history_module.dart';
import 'package:yhdm/repositories/download_repository.dart';
import 'package:yhdm/services/download/download_manager.dart';
import 'package:yhdm/services/video_source/video_source_format.dart';
import 'package:yhdm/services/video_source/services.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:mobx/mobx.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/player/player_error_mapper.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yhdm/modules/bangumi/episode_item.dart';
import 'package:yhdm/modules/comments/comment_item.dart';
import 'package:yhdm/modules/comments/comment_response.dart';
import 'package:yhdm/request/apis/bangumi_api.dart';
import 'package:flutter/material.dart';
import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:yhdm/modules/danmaku/danmaku_module.dart';
import 'package:yhdm/request/apis/custom_danmaku_api.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/utils/device.dart';
import 'package:yhdm/utils/episode_url.dart';
import 'package:yhdm/utils/http_headers.dart';
import 'package:yhdm/utils/media.dart';
import 'package:yhdm/utils/async_session.dart';
import 'package:yhdm/services/platform/display_mode_service.dart';
import 'package:yhdm/plugins/plugins_controller.dart';
import 'package:yhdm/modules/search/plugin_search_module.dart';
import 'package:yhdm/services/storage/settings_keys.dart';
import 'package:yhdm/repositories/history_repository.dart';
import 'package:yhdm/services/plugin/rule_engine_models.dart';

part 'video_controller.g.dart';

class VideoPageController extends _VideoPageController
    with _$VideoPageController {
  VideoPageController(
    super.historyController,
    super.downloadRepository,
    super.downloadManager,
  );

  /// 首次进入播放页前由"连播队列"设置的起始集（episode, road），播放后即清空
  static (int, int)? pendingQueueEpisode;

  /// 🆕 好友"一起看"邀请：打开播放页后自动加入该 Syncplay 房间
  static ({int id, int episode, String room, String endpoint, String username})?
      pendingSyncInvite;

  /// ⭐ 详情页预解析池：key='番剧id:集数' → 直链 URL。
  /// 详情页选源后后台预解析第 1 集写入，播放页 changeEpisode 命中即秒开。
  static final Map<String, String> incomingPreloadedUrls = {};

  /// 详情页后台预解析指定集数直链（失败静默，不影响详情页）
  static Future<void> preloadFor(
    int bangumiId,
    int episode, {
    required Plugin currentPlugin,
    required String pageUrl,
  }) async {
    final key = '$bangumiId:$episode';
    if (incomingPreloadedUrls.containsKey(key)) return;
    final service = WebViewVideoSourceService();
    try {
      final urlItem = normalizeEpisodeUrl(currentPlugin.baseUrl, pageUrl);
      final source = await service.resolve(
        urlItem,
        useLegacyParser: currentPlugin.useLegacyParser,
        offset: 0,
      );
      if (source.url.isNotEmpty) {
        incomingPreloadedUrls[key] = source.url;
        KazumiLogger().i(
            'VideoPageController: 详情页预解析完成 $bangumiId 第$episode集');
      }
    } catch (e) {
      KazumiLogger().w('VideoPageController: 详情页预解析失败', error: e);
    } finally {
      unawaited(service.dispose());
    }
  }
}

class VideoEpisodeSelection {
  const VideoEpisodeSelection({
    required this.episode,
    required this.road,
  });

  final int episode;
  final int road;

  @override
  bool operator ==(Object other) {
    return other is VideoEpisodeSelection &&
        other.episode == episode &&
        other.road == road;
  }

  @override
  int get hashCode => Object.hash(episode, road);

  @override
  String toString() {
    return 'VideoEpisodeSelection(episode: $episode, road: $road)';
  }
}

abstract class _VideoPageController with Store implements Disposable {
  _VideoPageController(
    this.historyController,
    this.downloadRepository,
    this.downloadManager,
  );

  late BangumiItem bangumiItem;
  EpisodeInfo episodeInfo = EpisodeInfo.fromTemplate();

  @observable
  var episodeCommentsList = ObservableList<EpisodeCommentItem>();

  // Resolution state machine: [_beginEpisodeSwitch] enters the loading state;
  // [_finishLoading] and [_failLoading] are the only terminal transitions.
  // [_errorMessage] is non-null only in the failed state.
  @readonly
  bool _loading = true;

  @readonly
  String? _errorMessage;

  @observable
  VideoEpisodeSelection selectedEpisode =
      const VideoEpisodeSelection(episode: 1, road: 0);

  @observable
  VideoEpisodeSelection? playingEpisode;

  /// 预加载的下一集视频地址缓存（集数 → 直链）
  final Map<int, String> _preloadedVideoUrls = {};
  bool _preloadInFlight = false;

  /// 伪装 HLS 失败回退嗅探命中的强制格式（失败重试时置位，供 init 使用）
  VideoSourceFormat forcedSourceFormat = VideoSourceFormat.auto;

  /// 预加载专用的独立解析实例（不干扰主播放的 webview 解析）
  WebViewVideoSourceService? _preloadVideoSourceService;

  /// 🔧 预加载失败冷却：{集数 → 解除时间戳}，失败后 60 秒内不再重试该集（避免反复请求导致限流/刷日志）
  final Map<int, int> _preloadCooldownUntil = {};

  bool _isPreloadCooling(int index) {
    final until = _preloadCooldownUntil[index];
    if (until == null) return false;
    if (DateTime.now().millisecondsSinceEpoch < until) return true;
    _preloadCooldownUntil.remove(index);
    return false;
  }

  void _markPreloadCooldown(int index, {int seconds = 60}) {
    _preloadCooldownUntil[index] =
        DateTime.now().millisecondsSinceEpoch + seconds * 1000;
  }

  /// 预加载被主播放解析抢占（换集/重新解析）后，3 秒自动补一次
  Timer? _preloadRetryTimer;

  void _schedulePreloadRetry(int episode, int road) {
    _preloadRetryTimer?.cancel();
    _preloadRetryTimer = Timer(const Duration(seconds: 3), () {
      _preloadRetryTimer = null;
      _triggerPreloadForEpisode(episode, road);
    });
  }


  /// ⭐ 主动预加载指定集数（手动点击下一集时触发）
  void _triggerPreloadForEpisode(int episode, int road) {
    if (!GStorage.getSetting(SettingsKeys.preloadNextEpisode)) return;
    if (isOfflineMode) return;
    if (_preloadInFlight) return;
    if (roadList.isEmpty) return;
    
    final resolved = _resolveOnlineEpisode(episode, road: road);
    if (resolved == null) return;
    // 🔧 冷却期内不重试
    if (_isPreloadCooling(resolved.listIndex)) return;
    if (_preloadedVideoUrls.containsKey(resolved.listIndex)) {
      KazumiLogger().i('⏭️ 下一集已缓存: 第${resolved.listIndex}集');
      return;
    }
    
    _preloadInFlight = true;
    final urlItem = normalizeEpisodeUrl(
      currentPlugin.baseUrl,
      resolved.pageUrl,
    );
    
    KazumiLogger().i('⏳ 预加载下一集: 第${resolved.listIndex}集 (${resolved.displayTitle})');
    
    // 🔧 预加载用独立解析实例：不共用主播放的 webview，避免并发互相打断
    _preloadVideoSourceService ??= WebViewVideoSourceService();
    _preloadVideoSourceService!.resolve(
      urlItem,
      useLegacyParser: currentPlugin.useLegacyParser,
      offset: 0,
    ).then((source) {
      if (source.url.isNotEmpty) {
        _preloadedVideoUrls[resolved.listIndex] = source.url;
        KazumiLogger().i('✅ 预加载完成: 第${resolved.listIndex}集');
      }
    }).catchError((Object e) {
      // ⭐ 被主播放解析接管（换集/重新解析）不算真失败：
      // 不进 60s 冷却，3 秒后自动补一次，确保下一集能提前解析好。
      if (e is VideoSourceCancelledException) {
        _schedulePreloadRetry(episode, road);
        KazumiLogger()
            .i('⏳ 预加载被主解析接管，稍后自动重试: 第${resolved.listIndex}集');
        return;
      }
      // 🔧 真失败（超时等）进入冷却，避免反复请求触发限流
      _markPreloadCooldown(resolved.listIndex);
      KazumiLogger().w('⚠️ 预加载失败(已进入冷却): 第${resolved.listIndex}集', error: e);
    }).whenComplete(() {
      _preloadInFlight = false;
    });
  }

  /// 预加载下一集：接近结尾时提前解析视频直链，连播秒开（设置可关）
  Future<void> preloadNextEpisode() async {
    if (!GStorage.getSetting(SettingsKeys.preloadNextEpisode)) return;
    if (isOfflineMode || _loading || _preloadInFlight) return;
    final current = playingEpisode ?? selectedEpisode;
    final next = current.episode + 1;
    final resolved = _resolveOnlineEpisode(next, road: current.road);
    if (resolved == null) return;
    if (_preloadedVideoUrls.containsKey(resolved.listIndex)) return;
    _preloadInFlight = true;
    try {
      final urlItem = normalizeEpisodeUrl(
        currentPlugin.baseUrl,
        resolved.pageUrl,
      );
      // 🔧 独立解析实例，避免与主播放的 webview 解析互相打断
      _preloadVideoSourceService ??= WebViewVideoSourceService();
      final source = await _preloadVideoSourceService!.resolve(
        urlItem,
        useLegacyParser: currentPlugin.useLegacyParser,
        offset: 0,
      );
      if (source.url.isNotEmpty) {
        _preloadedVideoUrls[resolved.listIndex] = source.url;
        KazumiLogger().i(
            'VideoPageController: 预加载下一集 ${resolved.listIndex} 完成');
      }
    } catch (e) {
      // ⭐ 被主播放解析抢占时 3 秒后自动补一次，不算失败不冷却
      if (e is VideoSourceCancelledException) {
        _schedulePreloadRetry(next, current.road);
        KazumiLogger()
            .i('VideoPageController: 预加载被主解析接管，稍后自动重试 第$next集');
      } else {
        _markPreloadCooldown(resolved.listIndex);
        KazumiLogger()
            .w('VideoPageController: 预加载下一集失败(已进入冷却)', error: e);
      }
    } finally {
      _preloadInFlight = false;
    }
  }

  /// 直接使用预加载的直链播放（跳过解析，秒开）
  Future<void> _playWithPreloadedUrl(
    String videoUrl,
    int offset, {
    required EpisodeRef resolvedEpisode,
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    if (session.isStale) return;
    _finishLoading();
    KazumiLogger().i(
        'VideoPageController: ✅ 使用预加载直链播放 ${resolvedEpisode.listIndex}');

    // 🔧 预加载直链若是伪装流（非标准后缀）也快速嗅探一次，确保秒开能播
    var videoFormat = forcedSourceFormat;
    if (videoFormat == VideoSourceFormat.auto &&
        !isStandardVideoUrl(videoUrl)) {
      try {
        videoFormat = await sniffHlsFormat(
          videoUrl,
          headers: {
            'user-agent': currentPlugin.userAgent.isEmpty
                ? getRandomUA()
                : currentPlugin.userAgent,
            if (currentPlugin.referer.isNotEmpty)
              'referer': currentPlugin.referer,
          },
        );
        if (videoFormat == VideoSourceFormat.hls) {
          KazumiLogger().i(
              'VideoPageController: 预加载直链嗅探命中 HLS: $videoUrl');
        }
      } catch (_) {
        videoFormat = VideoSourceFormat.auto;
      }
    }

    final params = PlaybackInitParams(
      videoUrl: videoUrl,
      offset: offset,
      isLocalPlayback: false,
      videoSourceFormat: videoFormat,
      bangumiId: bangumiItem.id,
      pluginName: currentPlugin.name,
      episode: resolvedEpisode.listIndex,
      danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
      pageUrl: resolvedEpisode.pageUrl,
      sortNumber: resolvedEpisode.sortNumber,
      httpHeaders: currentPlugin.buildHttpHeaders(),
      adBlockerEnabled: false,
      episodeTitle: resolvedEpisode.displayTitle,
      referer: '',
      currentRoad: resolvedEpisode.roadIndex,
      coverUrl: bangumiItem.images['large'],
      bangumiName: bangumiItem.nameCn.isNotEmpty
          ? bangumiItem.nameCn
          : bangumiItem.name,
    );
    final initialized = await playerController.init(params);
    if (session.isActive && initialized) {
      playingEpisode = VideoEpisodeSelection(
        episode: resolvedEpisode.listIndex,
        road: resolvedEpisode.roadIndex,
      );
      unawaited(_loadPlaybackDanmaku(playerController, params, session));
    } else if (session.isActive) {
      _playbackSessions.cancel();
    }
  }

  @observable
  int commentsEpisode = 1;

  @action
  void resetEpisodeState({int episode = 1, int road = 0}) {
    final selection = VideoEpisodeSelection(episode: episode, road: road);
    selectedEpisode = selection;
    playingEpisode = null;
    commentsEpisode = commentEpisodeForSelection(selection);
  }

  VideoEpisodeSelection get playbackEpisode =>
      playingEpisode ?? selectedEpisode;

  @observable
  bool isFullscreen = false;

  @observable
  bool isCommentsAscending = false;

  // Playback, automatic danmaku loading, and comment loading have separate
  // owners. Manual danmaku selection can cancel auto danmaku without touching
  // playback; comment refreshes never cancel playback.
  final AsyncSessionOwner _playbackSessions = AsyncSessionOwner();
  final AsyncSessionOwner _danmakuSessions = AsyncSessionOwner();
  final AsyncSessionOwner _commentSessions = AsyncSessionOwner();

  @observable
  bool isPip = false;

  @observable
  bool showTabBody = true;

  @observable
  int historyOffset = 0;

  @observable
  bool isOfflineMode = false;

  PlaybackHistoryIdentity? _playbackHistoryIdentity;
  final Map<int, DownloadEpisode> _offlineEpisodesByNumber = {};
  final Map<int, int> _offlineDisplayRoadToOriginalRoad = {};
  final Map<int, int> _offlineOriginalRoadToDisplayRoad = {};

  /// Title reported by the video source; may differ from [bangumiItem]'s.
  String title = '';

  String src = '';

  @observable
  var roadList = ObservableList<Road>();

  late Plugin currentPlugin;

  // ─── 🆕 自动解析模式（AnimeFlow式：直接进播放页，页内自动选源） ───
  /// 是否处于「未指定源、进入播放页后自动解析」模式
  bool _autoResolvePending = false;

  /// 自动解析的加载状态文案（正在搜索线路... / 正在解析 xx...）
  /// 普通字段即可：首次赋值伴随 _loading=true 触发一次重建，
  /// 解析完成由 _finishLoading/_failLoading 响应式收尾。
  String? autoResolveStatus;

  /// 自动解析搜索到的全部候选源（供播放页「切换线路」面板使用）
  List<PluginSearchResponse> autoResolveCandidates = [];

  /// 需要验证码的源（搜索时抛 CaptchaRequiredException 记录，供换源面板展示）
  Set<String> captchaSourceNames = {};

  bool get isAutoResolvePending => _autoResolvePending;

  /// 当前生效源名称；自动解析未完成时 currentPlugin 可能未赋值，安全读取
  String get activePluginName {
    try {
      return currentPlugin.name;
    } catch (_) {
      return '';
    }
  }

  /// 进入自动解析模式：详情页点「开始观看」直接进播放页时调用
  void enterAutoResolveMode() {
    _autoResolvePending = true;
    _loading = true;
    _errorMessage = null;
    autoResolveStatus = '正在搜索线路...';
  }

  String _offlinePluginName = '';

  final HistoryController historyController;
  final IDownloadRepository downloadRepository;
  final IDownloadManager downloadManager;

  WebViewVideoSourceService? _videoSourceService;

  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();

  Stream<String> get logStream => _logStreamController.stream;

  StreamSubscription<String>? _logSubscription;

  /// Applies the route arguments exactly once, from [VideoPage.initState].
  @action
  void applyPlaybackArgs(VideoPlaybackArgs args) {
    switch (args) {
      case OnlineVideoPlaybackArgs():
        bangumiItem = args.bangumiItem;
        currentPlugin = args.plugin;
        title = args.title;
        src = args.src;
        roadList.clear();
        roadList.addAll(args.roads);
      case AutoResolveVideoPlaybackArgs():
        // 🆕 AnimeFlow式：未指定源，进入播放页后自动搜索+选源+解析
        bangumiItem = args.bangumiItem;
        enterAutoResolveMode();
      case OfflineVideoPlaybackArgs():
        _initForOfflinePlayback(
          bangumiItem: args.bangumiItem,
          pluginName: args.pluginName,
          episodeNumber: args.episodeNumber,
          road: args.road,
          downloadedEpisodes: args.downloadedEpisodes,
        );
    }
  }

  // ─── 🆕 自动解析核心流程（AnimeFlow式） ──────────────────────────────

  /// 播放页初始化后调用：自动 搜索全部源 → 评分选优 → 解析分集 → 播放。
  /// 解析失败的源自动换下一个，全部失败才提示。
  Future<void> autoResolveAndPlay({
    required PlayerController playerController,
  }) async {
    if (!_autoResolvePending || isOfflineMode) return;
    autoResolveStatus = '正在搜索线路...';
    // 🆕 搜索关键词候选：中文名优先，原名/别名兜底
    //    （中文名为空、或中文名搜到的源太少时，用原名/别名补搜）
    final searchKeywords = <String>[
      if (bangumiItem.nameCn.isNotEmpty) bangumiItem.nameCn,
      bangumiItem.name,
      ...bangumiItem.alias,
    ]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (searchKeywords.isEmpty) {
      _autoResolvePending = false;
      autoResolveStatus = null;
      _failLoading('番剧名为空，无法搜索');
      return;
    }

    // 🆕 选源阶段就提前预取弹幕（不等源确定，先按历史集数预取弹弹play）
    unawaited(() async {
      try {
        final historyRepo = inject<IHistoryRepository>();
        final ep = historyRepo
                .getHistory('', bangumiItem)
                ?.lastWatchEpisode ??
            1;
        await playerController.danmaku
            .prefetchDanDan(bangumiItem.id, ep < 1 ? 1 : ep);
      } catch (_) {}
    }());

    // 🆕 主关键词搜索：先出先用（minResults=1）；命中太少再用原名/别名补搜
    var results = await _searchAllSources(searchKeywords.first, minResults: 1);
    if (!_autoResolvePending) return;
    // 🆕 主关键词命中太少 → 用原名/别名补搜（最多再补 2 个词），按源名合并去重
    if (results.length < 2 && searchKeywords.length > 1) {
      for (final kw in searchKeywords.skip(1).take(2)) {
        if (!_autoResolvePending) return;
        final more = await _searchAllSources(kw, minResults: 1);
        for (final r in more) {
          final i =
              results.indexWhere((e) => e.pluginName == r.pluginName);
          if (i < 0) {
            results.add(r);
          } else if (r.data.length > results[i].data.length) {
            results[i] = r;
          }
        }
      }
    }
    if (!_autoResolvePending) return;

    // 评分排序（标星规则永远最优先，与详情页选源面板同一套规则）
    final sorted = List<PluginSearchResponse>.from(results)
      ..sort((a, b) =>
          _scoreAutoResolveSource(b).compareTo(_scoreAutoResolveSource(a)));
    autoResolveCandidates = sorted;

    for (final resp in sorted) {
      if (!_autoResolvePending) return;
      final plugin = findPluginByName(resp.pluginName);
      if (plugin == null) continue;
      if (resp.data.isEmpty) continue;
      autoResolveStatus = '正在解析 ${resp.pluginName}...';
      try {
        final roads = await plugin.queryChapterRoads(resp.data.first.src);
        if (roads.isEmpty) continue;
        // 应用源：标题/直链分集列表全部就位，进入正常播放流程
        applyAutoResolvedSource(
          plugin: plugin,
          title: resp.data.first.name,
          src: resp.data.first.src,
          roads: roads,
        );
        // 读取历史：看过则续播上次集数，否则第 1 集
        final historyRepo = inject<IHistoryRepository>();
        var episode =
            historyRepo.getHistory(plugin.name, bangumiItem)?.lastWatchEpisode ??
                1;
        if (episode < 1 || episode > roads.first.data.length) episode = 1;
        _autoResolvePending = false;
        autoResolveStatus = null;
        await changeEpisode(
          episode,
          currentRoad: 0,
          playerController: playerController,
        );
        // 🆕 如果选中的是标星规则，明确提示用户（否则不知道为什么直接用它）
        if (_isStarred(plugin.name)) {
          KazumiDialog.showToast(message: '已优先使用标星规则「${plugin.name}」');
        }
        return;
      } catch (e) {
        KazumiLogger().w(
            'AutoResolve: ${resp.pluginName} 解析失败，换下一个源',
            error: e);
        continue;
      }
    }
    _autoResolvePending = false;
    autoResolveStatus = null;
    _failLoading('所有线路均解析失败，请重试或更换番剧');
  }

  /// 把自动选中的源应用到播放页（标题/分集列表就位）
  @action
  void applyAutoResolvedSource({
    required Plugin plugin,
    required String title,
    required String src,
    required List<Road> roads,
  }) {
    currentPlugin = plugin;
    this.title = title;
    this.src = src;
    roadList.clear();
    roadList.addAll(roads);
    forcedSourceFormat = VideoSourceFormat.auto;
  }

  /// 并发搜索全部可用源（受限并发 5，合集展开为子规则）。
  /// 🆕 [minResults]：累计够这么多可用结果就提前返回，不等慢源。
  /// 并发搜索全部可用源（受限并发，合集展开为子规则）。
  ///
  /// 🆕 速度优先策略（解决「一直正在解析」）：
  /// - 按「优先级」顺序发起：标星 → 历史验证可用 → 其余
  /// - 只要累计够 [minResults] 个可用结果就立刻返回，不等慢源
  /// - 默认 [minResults]=1：谁先搜出结果就用谁，剩余慢源直接放弃
  Future<List<PluginSearchResponse>> _searchAllSources(
    String keyword, {
    int minResults = 1,
  }) async {
    final pluginsController = inject<PluginsController>();
    final plugins = <Plugin>[];
    for (final p in pluginsController.pluginList) {
      if (!p.enabled) continue;
      if (p.isCollection) {
        for (final child in p.childPlugins) {
          if (child.enabled && child.searchURL.isNotEmpty) {
            plugins.add(child);
          }
        }
      } else {
        plugins.add(p);
      }
    }
    // 🆕 优先级排序：标星最前，其次历史验证可用的源，最后其余
    final starSet =
        GStorage.getStringListSettingByName('starRules').toSet();
    final tracker = pluginsController.validityTracker;
    int priority(Plugin p) {
      if (starSet.contains(p.name)) return 0;
      if (tracker.isSearchValid(p.name)) return 1;
      return 2;
    }
    plugins.sort((a, b) => priority(a).compareTo(priority(b)));

    final results = <PluginSearchResponse>[];
    captchaSourceNames.clear();
    // 并发数适中：太大反而拖慢单个源、触发风控
    const maxConcurrent = 4;
    var next = 0;
    var enough = false; // 够数标志，worker 见此即停
    Future<void> worker() async {
      while (true) {
        if (enough) return;
        final i = next++;
        if (i >= plugins.length) return;
        final plugin = plugins[i];
        try {
          // ⚠️ 不因 needLogin 而跳过搜索：很多站点（如次元城）搜索接口无需登录，
          // 只有播放/解析章节才需要。跳过后源会从列表消失，用户以为「不能用」。
          // 未登录的源搜索结果仍会进入候选；真正播放失败时再提示去登录。
          final result =
              await plugin.queryBangumi(keyword, shouldRethrow: true);
          if (enough) return;
          if (result.data.isNotEmpty) {
            results.add(result);
            // 🆕 够 minResults 个可用结果就提前收工，不等其余慢源
            if (results.length >= minResults) {
              enough = true;
              return;
            }
          }
        } on CaptchaRequiredException {
          // 🆕 需要验证码：记录下来，换源面板显示盾牌，点击可验证
          captchaSourceNames.add(plugin.name);
        } catch (_) {
          // 单源失败静默，交给评分排序跳过
        }
      }
    }

    await Future.wait(
      List.generate(maxConcurrent.clamp(1, plugins.length), (_) => worker()),
    );
    return results;
  }

  /// 是否已标星（starRules）
  bool _isStarred(String pluginName) {
    try {
      return GStorage
          .getStringListSettingByName('starRules')
          .contains(pluginName);
    } catch (_) {
      return false;
    }
  }

  /// 与详情页选源面板一致的源评分规则
  int _scoreAutoResolveSource(PluginSearchResponse resp) {
    var score = 0;
    // 🆕 标星规则永远优先（用户在规则设置里标星的源）
    if (_isStarred(resp.pluginName)) score += 10000;
    final useDefault = GStorage.getSetting(SettingsKeys.ruleSortDefault);
    final byQuality = GStorage.getSetting(SettingsKeys.ruleSortQuality);
    final byEpisodes = GStorage.getSetting(SettingsKeys.ruleSortEpisodes);
    final bySpeed = GStorage.getSetting(SettingsKeys.ruleSortSpeed);
    if (useDefault && !byQuality && !byEpisodes && !bySpeed) {
      return score;
    }
    if (byEpisodes) {
      score += resp.data.length * 10;
    }
    if (byQuality) {
      final text = resp.data
          .map((s) => '${s.name} ${s.src}')
          .join(' ')
          .toLowerCase();
      if (RegExp(r'1080|2160|4k|hd|高清|超清|bluray|web-dl')
          .hasMatch(text)) {
        score += 100;
      }
    }
    if (bySpeed) {
      score += 1;
    }
    return score;
  }

  /// 按插件名查找插件（主列表 + 合集子规则）
  Plugin? findPluginByName(String name) {
    final pluginsController = inject<PluginsController>();
    for (final p in pluginsController.pluginList) {
      if (p.name == name) return p;
      if (p.isCollection) {
        for (final child in p.childPlugins) {
          if (child.name == name) return child;
        }
      }
    }
    return null;
  }

  @action
  void _initForOfflinePlayback({
    required BangumiItem bangumiItem,
    required String pluginName,
    required int episodeNumber,
    required int road,
    required List<DownloadEpisode> downloadedEpisodes,
  }) {
    this.bangumiItem = bangumiItem;
    _offlinePluginName = pluginName;
    title =
        bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;
    isOfflineMode = true;
    _loading = false;

    _buildOfflineRoadList(downloadedEpisodes);

    final target = _findOfflineEpisodeByNumber(
      episodeNumber,
      preferredOriginalRoad: road,
    );
    final selected = VideoEpisodeSelection(
      episode: target?.listIndex ?? 1,
      road: target?.roadIndex ?? 0,
    );
    selectedEpisode = selected;
    playingEpisode = null;
    commentsEpisode = commentEpisodeForSelection(selected);
    final resolvedEpisode = _resolveOfflineEpisode(
      selected.episode,
      road: selected.road,
    );
    if (resolvedEpisode != null) {
      _setOfflineHistoryIdentity(resolvedEpisode);
    } else {
      _playbackHistoryIdentity = null;
    }
    KazumiLogger().i(
        'VideoPageController: initialized for offline playback, episode $episodeNumber (position: ${selected.episode})');
  }

  void _buildOfflineRoadList(List<DownloadEpisode> episodes) {
    final snapshot = buildOfflineRoadListSnapshot(episodes);
    roadList.clear();
    roadList.addAll(snapshot.roads);
    _offlineEpisodesByNumber.clear();
    _offlineEpisodesByNumber.addAll(snapshot.episodesByNumber);
    _offlineDisplayRoadToOriginalRoad.clear();
    _offlineDisplayRoadToOriginalRoad
        .addAll(snapshot.displayRoadToOriginalRoad);
    _offlineOriginalRoadToDisplayRoad.clear();
    _offlineOriginalRoadToDisplayRoad
        .addAll(snapshot.originalRoadToDisplayRoad);
  }

  String get offlinePluginName => _offlinePluginName;

  PlaybackHistoryIdentity? get currentHistoryIdentity =>
      _playbackHistoryIdentity;

  ({int listIndex, int roadIndex})? _findOfflineEpisodeByNumber(
    int episodeNumber, {
    required int preferredOriginalRoad,
  }) {
    if (episodeNumber <= 0 || roadList.isEmpty) {
      return null;
    }
    final preferredDisplayRoad =
        _offlineOriginalRoadToDisplayRoad[preferredOriginalRoad];
    final roadIndices = <int>[
      if (preferredDisplayRoad != null) preferredDisplayRoad,
      for (var i = 0; i < roadList.length; i++)
        if (i != preferredDisplayRoad) i,
    ];
    for (final roadIndex in roadIndices) {
      final match = _findOfflineEpisodeInDisplayRoad(episodeNumber, roadIndex);
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  ({int listIndex, int roadIndex})? _findOfflineEpisodeInDisplayRoad(
    int episodeNumber,
    int roadIndex,
  ) {
    if (roadIndex < 0 || roadIndex >= roadList.length) {
      return null;
    }
    final index = roadList[roadIndex].data.indexOf(episodeNumber.toString());
    if (index < 0) {
      return null;
    }
    return (listIndex: index + 1, roadIndex: roadIndex);
  }

  int getHistoryOffsetFor(PlaybackHistoryIdentity identity) {
    final playResume = GStorage.getSetting(SettingsKeys.playResume);
    if (playResume != true) {
      return 0;
    }
    return historyController
            .findProgress(
              identity.bangumiItem,
              identity.pluginName,
              identity.episodeNumber,
              entryKind: identity.entryKind,
            )
            ?.progress
            .inSeconds ??
        0;
  }

  void _setOnlineHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.online(
      bangumiItem: bangumiItem,
      pluginName: currentPlugin.name,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      onlineBangumiSrc: src,
      episodePageUrl: episode.pageUrl,
    );
  }

  void _setOfflineHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.offline(
      bangumiItem: bangumiItem,
      pluginName: _offlinePluginName,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      episodePageUrl: episode.pageUrl,
    );
  }

  EpisodeRef? _resolveOnlineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final displayTitle = roadData.identifier[index];
    return EpisodeRef.online(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: displayTitle,
      pageUrl: roadData.data[index],
    );
  }

  EpisodeRef? _resolveOfflineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final episodeNumber = int.tryParse(roadData.data[index]);
    if (episodeNumber == null) {
      return null;
    }
    final downloadEpisode = _offlineEpisodesByNumber[episodeNumber];
    final titleFromRoad = roadData.identifier[index];
    final episodeTitle = downloadEpisode?.episodeName.isNotEmpty == true
        ? downloadEpisode!.episodeName
        : (titleFromRoad.isNotEmpty ? titleFromRoad : '第$episodeNumber集');
    return EpisodeRef.offline(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: episodeTitle,
      pageUrl: downloadEpisode?.episodePageUrl ?? '',
      episodeNumber: episodeNumber,
      originalRoadIndex: downloadEpisode?.road ??
          _offlineDisplayRoadToOriginalRoad[targetRoad] ??
          targetRoad,
    );
  }

  EpisodeRef? resolveEpisode(VideoEpisodeSelection selection) {
    return isOfflineMode
        ? _resolveOfflineEpisode(selection.episode, road: selection.road)
        : _resolveOnlineEpisode(selection.episode, road: selection.road);
  }

  int commentEpisodeForSelection(VideoEpisodeSelection selection) {
    final resolvedEpisode = resolveEpisode(selection);
    return resolvedEpisode?.danmakuEpisodeNumber ?? selection.episode;
  }

  /// Resets pre-switch state as a single transaction so observers see one
  /// notification instead of one per field.
  @action
  void _beginEpisodeSwitch(VideoEpisodeSelection selection) {
    final targetCommentsEpisode = commentEpisodeForSelection(selection);
    selectedEpisode = selection;
    playingEpisode = null;
    // The comments sheet only re-queries when [commentsEpisode] changes, so
    // resetting comment state here without changing it would blank the sheet
    // permanently.
    if (targetCommentsEpisode != commentsEpisode) {
      commentsEpisode = targetCommentsEpisode;
      _resetEpisodeComments();
    }
    _loading = true;
    _errorMessage = null;
  }

  @action
  void _applyResolvedSelection(EpisodeRef resolvedEpisode) {
    selectedEpisode = VideoEpisodeSelection(
      episode: resolvedEpisode.listIndex,
      road: resolvedEpisode.roadIndex,
    );
    commentsEpisode = commentEpisodeForSelection(selectedEpisode);
  }

  @action
  void _finishLoading() {
    _loading = false;
  }

  @action
  void _failLoading(String message) {
    _loading = false;
    _errorMessage = message;
  }

  /// ⭐ 修改：切换集数（支持预加载缓存）
  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
    required PlayerController playerController,
  }) async {
    final session = _playbackSessions.begin();
    final selection = VideoEpisodeSelection(
      episode: episode,
      road: currentRoad,
    );
    _beginEpisodeSwitch(selection);
    _danmakuSessions.cancel();
    playerController.danmaku.finishDanmakuLoad();
    _videoSourceService?.cancel();

    await playerController.stop();
    if (session.isStale) {
      return;
    }

    if (isOfflineMode) {
      await _changeOfflineEpisode(
        selection,
        offset,
        session: session,
        playerController: playerController,
      );
      return;
    }

    final resolvedEpisode = _resolveOnlineEpisode(episode, road: currentRoad);
    if (resolvedEpisode == null) {
      KazumiLogger().e(
          'VideoPageController: failed to resolve online episode. road=$currentRoad, episode=$episode');
      _failLoading('集数解析失败');
      return;
    }

    _applyResolvedSelection(resolvedEpisode);
    _setOnlineHistoryIdentity(resolvedEpisode);

    KazumiLogger()
        .i('VideoPageController: changed to ${resolvedEpisode.displayTitle}');
    final urlItem = normalizeEpisodeUrl(
      currentPlugin.baseUrl,
      resolvedEpisode.pageUrl,
    );

    // ⭐ 检查预加载缓存（秒开）
    // 先吸收详情页预解析池的直链（命中即移除，只生效一次）
    final incomingKey = '${bangumiItem.id}:${resolvedEpisode.listIndex}';
    final incomingUrl =
        VideoPageController.incomingPreloadedUrls.remove(incomingKey);
    if (incomingUrl != null && incomingUrl.isNotEmpty) {
      _preloadedVideoUrls[resolvedEpisode.listIndex] = incomingUrl;
      KazumiLogger().i(
          '✅ 使用详情页预解析缓存: 第${resolvedEpisode.listIndex}集');
    }
    final preloadedUrl = _preloadedVideoUrls.remove(resolvedEpisode.listIndex);
    if (preloadedUrl != null && preloadedUrl.isNotEmpty) {
      KazumiLogger().i('✅ 使用预加载缓存: 第${resolvedEpisode.listIndex}集');
      await _playWithPreloadedUrl(
        preloadedUrl,
        offset,
        resolvedEpisode: resolvedEpisode,
        session: session,
        playerController: playerController,
      );
      // 播放当前集完成后，预加载下一集
      _triggerPreloadForEpisode(resolvedEpisode.listIndex + 1, currentRoad);
      return;
    }

    // ⭐ 没有缓存，正常解析
    KazumiLogger().i('⚠️ 无预加载缓存，正常解析: 第${resolvedEpisode.listIndex}集');
    await _resolveWithVideoSourceService(
      urlItem,
      offset,
      resolvedEpisode: resolvedEpisode,
      session: session,
      playerController: playerController,
    );
    
    // ⭐ 解析完成后，立即预加载下一集（下次点击秒开）
    _triggerPreloadForEpisode(resolvedEpisode.listIndex + 1, currentRoad);
  }

  Future<void> _changeOfflineEpisode(
    VideoEpisodeSelection selection,
    int offset, {
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    final resolvedEpisode =
        _resolveOfflineEpisode(selection.episode, road: selection.road);
    if (resolvedEpisode == null) {
      KazumiLogger().e(
          'VideoPageController: failed to resolve offline episode. road=${selection.road}, episode=${selection.episode}');
      _failLoading('集数解析失败');
      return;
    }

    final localPath = _getLocalVideoPath(
      bangumiItem.id,
      _offlinePluginName,
      resolvedEpisode.historyEpisodeNumber,
    );
    if (localPath == null) {
      _failLoading('该集数未下载');
      return;
    }
    _applyResolvedSelection(resolvedEpisode);
    _setOfflineHistoryIdentity(resolvedEpisode);
    if (session.isStale) {
      return;
    }
    _finishLoading();
    final resolvedOffset =
        offset > 0 ? offset : getHistoryOffsetFor(_playbackHistoryIdentity!);

    KazumiLogger().i(
        'VideoPageController: offline episode changed to ${resolvedEpisode.historyEpisodeNumber} (index: ${selection.episode}), path: $localPath');

    final params = PlaybackInitParams(
      videoUrl: localPath,
      offset: resolvedOffset,
      isLocalPlayback: true,
      bangumiId: bangumiItem.id,
      pluginName: _offlinePluginName,
      episode: resolvedEpisode.listIndex,
      danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
      pageUrl: resolvedEpisode.pageUrl,
      sortNumber: resolvedEpisode.sortNumber,
      httpHeaders: {},
      adBlockerEnabled: false,
      episodeTitle: resolvedEpisode.displayTitle,
      referer: '',
      currentRoad: resolvedEpisode.roadIndex,
      coverUrl: bangumiItem.images['large'],
      bangumiName:
          bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name,
    );

    final initialized = await playerController.init(params);
    if (session.isActive && initialized) {
      playingEpisode = selection;
      unawaited(_loadPlaybackDanmaku(playerController, params, session));
    } else if (session.isActive) {
      _playbackSessions.cancel();
    }
  }

  /// 拉取自建弹幕并合并显示（已审核/已发布的）
  Future<void> _loadCustomDanmakus(
    PlayerController playerController,
    PlaybackInitParams params,
  ) async {
    try {
      final items = await CustomDanmakuApi.fetch(
        bangumiId: params.bangumiId,
        // ⚠️ 用番剧集数（和发送时一致），不能用弹幕源集数，否则拉不到
        episode: params.episode,
      );
      if (items.isEmpty) {
        return;
      }
      playerController.danmaku.addDanmakus(
        items
            .map((e) => DanmakuEntry(
                  message: e.text,
                  time: e.timeMs / 1000.0,
                  type: e.type, // 1=滚动 4=底部 5=顶部（自己可发置顶/置底）
                  color: Colors.white,
                  source: 'Custom',
                ))
            .toList(),
      );
      // ⭐ 关键：确保弹幕开关打开。
      // 只开自建弹幕时，其他弹幕源返回空会走 applyUnavailableDanmakuLoad，
      // 它把 danmakuOn 置 false，导致自建弹幕加了也不显示。
      playerController.danmaku.danmakuOn = true;
      // ⭐ 以弹幕形式提示：前方自建弹幕数量（只统计樱花服务器的）
      playerController.danmaku.canvasController.addDanmaku(
        DanmakuContentItem(
          '前方 ${items.length} 条弹幕来袭',
          color: const Color(0xFFFF9800),
        ),
      );
      KazumiLogger()
          .i('VideoPageController: 合并自建弹幕 ${items.length} 条');
    } catch (e) {
      KazumiLogger().w('VideoPageController: 自建弹幕拉取失败', error: e);
    }
  }

  Future<void> _loadPlaybackDanmaku(
    PlayerController playerController,
    PlaybackInitParams params,
    AsyncSession session,
  ) async {
    final danmakuSession = _danmakuSessions.begin();
    // ⭐ 弹弹play 在解析/缓冲阶段就先进入搜索，先于其他来源；其余来源后台补。
    unawaited(playerController.danmaku.prefetchDanDan(
      params.bangumiId,
      params.danmakuEpisodeNumber,
    ));
    // 🔴 开始观看后再拉弹幕：等播放器真正播放（首帧/playing），
    // 避免弹幕请求抢视频首帧带宽导致开始变慢；用户不点播放则最多等 15 秒后照拉。
    if (!playerController.playback.playing) {
      final deadline =
          DateTime.now().add(const Duration(seconds: 15));
      while (session.isActive &&
          danmakuSession.isActive &&
          !playerController.playback.playing &&
          DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    playerController.danmaku.beginDanmakuLoad();
    try {
      final result = await playerController.danmaku.fetchDanmaku(
        params.bangumiId,
        params.pluginName,
        params.danmakuEpisodeNumber,
      );
      if (session.isActive && danmakuSession.isActive) {
        if (result.hasDanmakus) {
          // ⭐ 弹幕加载到即显示（恢复原行为，不再依赖"默认开启"开关；
          // 用户仍可用播放页内的弹幕开关随时关闭）
          playerController.danmaku.applyDanmakuLoad(
            result,
            enableDanmaku: true,
          );
        } else {
          playerController.danmaku.applyUnavailableDanmakuLoad(result);
          if (result.isFailed) {
            KazumiDialog.showToast(message: '弹幕加载失败，可手动检索');
          }
        }
      }
    } catch (e) {
      if (session.isActive && danmakuSession.isActive) {
        playerController.danmaku.finishDanmakuLoad(disableDanmaku: true);
        KazumiDialog.showToast(message: '弹幕加载失败，可手动检索');
      }
      KazumiLogger().w('VideoPageController: failed to load danmaku', error: e);
    }
    // ⭐ 自建弹幕"边看边抓"：延迟 2 秒再拉，不抢播放首帧带宽（前一两秒省略）
    if (session.isActive &&
        danmakuSession.isActive &&
        GStorage.getSetting(SettingsKeys.customDanmakuEnabled)) {
      unawaited(Future.delayed(const Duration(seconds: 2), () {
        if (!session.isActive || !danmakuSession.isActive) return;
        _loadCustomDanmakus(playerController, params);
      }));
    }
  }

  void cancelAutomaticDanmakuLoad() {
    _danmakuSessions.cancel();
  }

  String? _getLocalVideoPath(
      int bangumiId, String pluginName, int episodeNumber) {
    final episode =
        downloadRepository.getEpisode(bangumiId, pluginName, episodeNumber);
    return downloadManager.getLocalVideoPath(episode);
  }

  Future<void> _resolveWithVideoSourceService(
    String url,
    int offset, {
    required EpisodeRef resolvedEpisode,
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    // For RSS/direct media sources, skip WebView resolution
    if (currentPlugin.hasDirectMediaUrl) {
      if (session.isStale) return;
      _finishLoading();
      KazumiLogger()
          .i('VideoPageController: using direct media URL: $url');

      final params = PlaybackInitParams(
        videoUrl: url,
        offset: offset,
        isLocalPlayback: false,
        bangumiId: bangumiItem.id,
        pluginName: currentPlugin.name,
        episode: resolvedEpisode.listIndex,
        danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
        pageUrl: resolvedEpisode.pageUrl,
        sortNumber: resolvedEpisode.sortNumber,
        httpHeaders: currentPlugin.buildHttpHeaders(),
        adBlockerEnabled: false,
        episodeTitle: resolvedEpisode.displayTitle,
        referer: '',
        currentRoad: resolvedEpisode.roadIndex,
        coverUrl: bangumiItem.images['large'],
        bangumiName: bangumiItem.nameCn.isNotEmpty
            ? bangumiItem.nameCn
            : bangumiItem.name,
      );

      final initialized = await playerController.init(params);
      if (session.isActive && initialized) {
        playingEpisode = VideoEpisodeSelection(
          episode: resolvedEpisode.listIndex,
          road: resolvedEpisode.roadIndex,
        );
        unawaited(_loadPlaybackDanmaku(playerController, params, session));
      } else if (session.isActive) {
        _playbackSessions.cancel();
      }
      return;
    }

    _videoSourceService ??= WebViewVideoSourceService();

    await _logSubscription?.cancel();
    _logSubscription = _videoSourceService!.onLog.listen((log) {
      if (!_logStreamController.isClosed) {
        _logStreamController.add(log);
      }
    });

    try {
      final source = await _videoSourceService!.resolve(
        url,
        useLegacyParser: currentPlugin.useLegacyParser,
        offset: offset,
      );

      if (session.isStale) {
        return;
      }
      _finishLoading();
      KazumiLogger()
          .i('VideoPageController: resolved video URL: ${source.url}');

      final bool forceAdBlocker =
          GStorage.getSetting(SettingsKeys.forceAdBlocker);

      // 🆕 伪装 HLS 兼容改为"失败回退"（模仿官方 HLS 处理，省 0.3~1s）：
      // 主链路不再串行嗅探，直接按解析出的格式播放；
      // 若 mpv 加载失败（Failed to open），由 video_page 触发嗅探重试。
      VideoSourceFormat videoFormat =
          forcedSourceFormat != VideoSourceFormat.auto
              ? forcedSourceFormat
              : source.format;

      final params = PlaybackInitParams(
        videoUrl: source.url,
        offset: source.offset,
        isLocalPlayback: false,
        videoSourceFormat: videoFormat,
        bangumiId: bangumiItem.id,
        pluginName: currentPlugin.name,
        episode: resolvedEpisode.listIndex,
        danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
        pageUrl: resolvedEpisode.pageUrl,
        sortNumber: resolvedEpisode.sortNumber,
        httpHeaders: {
          'user-agent': currentPlugin.userAgent.isEmpty
              ? getRandomUA()
              : currentPlugin.userAgent,
          if (currentPlugin.referer.isNotEmpty)
            'referer': currentPlugin.referer,
        },
        adBlockerEnabled: forceAdBlocker || currentPlugin.adBlocker,
        episodeTitle: resolvedEpisode.displayTitle,
        referer: currentPlugin.referer,
        currentRoad: resolvedEpisode.roadIndex,
        coverUrl: bangumiItem.images['large'],
        bangumiName: bangumiItem.nameCn.isNotEmpty
            ? bangumiItem.nameCn
            : bangumiItem.name,
      );

      final initialized = await playerController.init(params);
      if (session.isActive && initialized) {
        playingEpisode = VideoEpisodeSelection(
          episode: resolvedEpisode.listIndex,
          road: resolvedEpisode.roadIndex,
        );
        unawaited(_loadPlaybackDanmaku(playerController, params, session));
      } else if (session.isActive) {
        _playbackSessions.cancel();
      }
    } on VideoSourceTimeoutException {
      if (session.isStale) {
        return;
      }
      _failLoading('视频解析超时，请重试');
    } on VideoSourceCancelledException {
      KazumiLogger().i('VideoPageController: video URL resolution cancelled');
    } catch (e) {
      if (session.isStale) {
        return;
      }
      // 网络抖动时只给一句简短提示，不再把整段异常文本丢给用户
      if (PlayerErrorMapper.isNetworkIssue(e)) {
        _failLoading('网络异常，视频加载失败，请重试');
      } else {
        _failLoading('视频解析失败：${e.toString()}');
      }
    }
  }

  void _resetEpisodeComments() {
    _commentSessions.cancel();
    episodeInfo.reset();
    episodeCommentsList.clear();
  }

  Future<bool> queryBangumiEpisodeCommentsByID(int id, int episode) async {
    final session = _commentSessions.begin();
    final EpisodeInfo latestEpisodeInfo;
    try {
      latestEpisodeInfo = await BangumiApi.getBangumiEpisodeByID(id, episode);
    } catch (_) {
      if (session.isStale) {
        return false;
      }
      rethrow;
    }
    if (session.isStale) {
      return false;
    }
    final EpisodeCommentResponse value;
    try {
      value =
          await BangumiApi.getBangumiCommentsByEpisodeID(latestEpisodeInfo.id);
    } catch (_) {
      if (session.isStale) {
        return false;
      }
      rethrow;
    }
    if (session.isStale) {
      return false;
    }
    final commentsList = value.commentList;
    if (!isCommentsAscending) {
      commentsList
          .sort((a, b) => b.comment.createdAt.compareTo(a.comment.createdAt));
    } else {
      commentsList
          .sort((a, b) => a.comment.createdAt.compareTo(b.comment.createdAt));
    }
    _applyEpisodeComments(episode, latestEpisodeInfo, commentsList);
    KazumiLogger().i(
        'VideoPageController: loaded comments list length ${episodeCommentsList.length}');
    return true;
  }

  @action
  void _applyEpisodeComments(
    int episode,
    EpisodeInfo info,
    List<EpisodeCommentItem> comments,
  ) {
    commentsEpisode = episode;
    episodeInfo = info;
    episodeCommentsList = ObservableList.of(comments);
  }

  @action
  void toggleSortOrder() {
    isCommentsAscending = !isCommentsAscending;
    episodeCommentsList.sort(
      (a, b) => isCommentsAscending
          ? a.comment.createdAt.compareTo(b.comment.createdAt)
          : b.comment.createdAt.compareTo(a.comment.createdAt),
    );
  }

  /// Called by Modular when the '/video' route scope is disposed.
  @override
  void dispose() {
    _preloadRetryTimer?.cancel();
    _preloadRetryTimer = null;
    _playbackSessions.cancel();
    _danmakuSessions.cancel();
    _commentSessions.cancel();
    _logSubscription?.cancel();
    _logSubscription = null;
    if (!_logStreamController.isClosed) {
      _logStreamController.close();
    }
    final videoSourceService = _videoSourceService;
    _videoSourceService = null;
    if (videoSourceService != null) {
      unawaited(videoSourceService.dispose());
    }
  }

  void enterFullScreen() {
    isFullscreen = true;
    DisplayModeService.applyVideoFullscreen(true);
  }

  void exitFullScreen() {
    isFullscreen = false;
    DisplayModeService.applyVideoFullscreen(false);
  }

  void isDesktopFullscreen() async {
    if (isDesktop()) {
      isFullscreen = await windowManager.isFullScreen();
    }
  }

  void handleOnEnterFullScreen() async {
    isFullscreen = true;
  }

  void handleOnExitFullScreen() async {
    isFullscreen = false;
  }
}

class OfflineRoadListSnapshot {
  const OfflineRoadListSnapshot({
    required this.roads,
    required this.episodesByNumber,
    required this.displayRoadToOriginalRoad,
    required this.originalRoadToDisplayRoad,
  });

  final List<Road> roads;
  final Map<int, DownloadEpisode> episodesByNumber;
  final Map<int, int> displayRoadToOriginalRoad;
  final Map<int, int> originalRoadToDisplayRoad;
}

OfflineRoadListSnapshot buildOfflineRoadListSnapshot(
  List<DownloadEpisode> episodes,
) {
  final groupedEpisodes = <int, List<DownloadEpisode>>{};
  final episodesByNumber = <int, DownloadEpisode>{};

  for (final episode in episodes) {
    episodesByNumber[episode.episodeNumber] = episode;
    groupedEpisodes.putIfAbsent(episode.road, () => []).add(episode);
  }

  final originalRoads = groupedEpisodes.keys.toList()..sort();
  final roads = <Road>[];
  final displayRoadToOriginalRoad = <int, int>{};
  final originalRoadToDisplayRoad = <int, int>{};

  for (final originalRoad in originalRoads) {
    final roadEpisodes = groupedEpisodes[originalRoad]!
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final displayRoad = roads.length;
    displayRoadToOriginalRoad[displayRoad] = originalRoad;
    originalRoadToDisplayRoad[originalRoad] = displayRoad;
    roads.add(Road(
      name: originalRoad >= 0
          ? '播放列表${originalRoad + 1}'
          : '播放列表${displayRoad + 1}',
      data: roadEpisodes.map((e) => e.episodeNumber.toString()).toList(),
      identifier: roadEpisodes
          .map((e) =>
              e.episodeName.isNotEmpty ? e.episodeName : '第${e.episodeNumber}集')
          .toList(),
    ));
  }

  return OfflineRoadListSnapshot(
    roads: roads,
    episodesByNumber: episodesByNumber,
    displayRoadToOriginalRoad: displayRoadToOriginalRoad,
    originalRoadToDisplayRoad: originalRoadToDisplayRoad,
  );
}

class EpisodeRef {
  const EpisodeRef({
    required this.listIndex,
    required this.roadIndex,
    required this.displayTitle,
    required this.pageUrl,
    required this.sortNumber,
    required this.historyEpisodeNumber,
    required this.danmakuEpisodeNumber,
    required this.originalRoadIndex,
  });

  final int listIndex;
  final int roadIndex;
  final String displayTitle;
  final String pageUrl;

  /// Episode sort number.
  /// - Online: parsed from [displayTitle] via [extractEpisodeNumber];
  ///   null when unparsable.
  /// - Offline: always the download record's episodeNumber.
  final int? sortNumber;
  final int historyEpisodeNumber;
  final int danmakuEpisodeNumber;
  final int originalRoadIndex;

  factory EpisodeRef.online({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
  }) {
    final parsedEpisodeNumber = extractEpisodeNumber(displayTitle);
    return EpisodeRef(
      listIndex: listIndex,
      roadIndex: roadIndex,
      displayTitle: displayTitle,
      pageUrl: pageUrl,
      sortNumber: parsedEpisodeNumber > 0 ? parsedEpisodeNumber : null,
      historyEpisodeNumber: listIndex,
      danmakuEpisodeNumber:
          parsedEpisodeNumber > 0 ? parsedEpisodeNumber : listIndex + 1,
      originalRoadIndex: roadIndex,
    );
  }

  const factory EpisodeRef.offline({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
    required int episodeNumber,
    required int originalRoadIndex,
  }) = _OfflineEpisodeRef;
}

class _OfflineEpisodeRef extends EpisodeRef {
  const _OfflineEpisodeRef({
    required super.listIndex,
    required super.roadIndex,
    required super.displayTitle,
    required super.pageUrl,
    required int episodeNumber,
    required super.originalRoadIndex,
  }) : super(
          sortNumber: episodeNumber,
          historyEpisodeNumber: episodeNumber,
          danmakuEpisodeNumber: episodeNumber,
        );
}
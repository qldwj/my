import 'dart:async';
import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/danmaku_send_sheet.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/pages/playlist/play_queue_page.dart';
import 'package:kazumi/services/playlist/play_queue_service.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/pages/player/player_item.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/request/apis/custom_danmaku_api.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/player/pip_utils.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:kazumi/pages/player/episode_comments_sheet.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/pages/download/download_episode_sheet.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/services/player/timed_shutdown_service.dart';
import 'package:kazumi/services/player/skip_segments_service.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/services/platform/display_mode_service.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.args,
    required this.playerController,
    required this.videoPageController,
    required this.historyController,
    required this.downloadController,
  });

  final VideoPlaybackArgs args;
  final PlayerController playerController;
  final VideoPageController videoPageController;
  final HistoryController historyController;
  final DownloadController downloadController;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with TickerProviderStateMixin, WindowListener {
  PlayerController get playerController => widget.playerController;
  VideoPageController get videoPageController => widget.videoPageController;
  bool _didInitializePlayback = false;
  bool _isClosing = false;
  HistoryController get historyController => widget.historyController;
  DownloadController get downloadController => widget.downloadController;
  late bool playResume;
  bool showDebugLog = false;
  List<String> webviewLogLines = [];
  StreamSubscription<String>? _logSubscription;
  final FocusNode keyboardFocus =
      FocusNode(debugLabel: 'Video player shortcut scope');

  ScrollController scrollController = ScrollController();
  late GridObserverController observerController;
  late AnimationController animation;
  late Animation<Offset> _rightOffsetAnimation;
  late Animation<double> _maskOpacityAnimation;
  late TabController tabController;

  int visibleRoad = 0;
  bool _tabBodyTargetVisible = true;
  int _tabBodyAnimationRun = 0;

  late final bool disableAnimations;

  StreamSubscription<SyncPlayChatMessage>? _syncChatSubscription;
  /// 源失效自动换源信号订阅
  StreamSubscription<void>? _sourceFailedSubscription;
  /// ⭐ 下一集预加载定时器（接近结尾触发）
  Timer? _preloadTimer;

  static const Duration _offlinePlayerInitDelay = Duration(milliseconds: 400);
  static const Duration _sideTabAnimationDuration = Duration(milliseconds: 120);

  @override
  void initState() {
    super.initState();
    videoPageController.applyPlaybackArgs(widget.args);
    // 🆕 预热连播队列（保证最后一集接播时 length 同步可用）
    unawaited(PlayQueueService.instance.getAll());
    // 🆕 连播队列：跳到记录的起始集
    final pending = VideoPageController.pendingQueueEpisode;
    if (pending != null) {
      VideoPageController.pendingQueueEpisode = null;
      videoPageController.selectedEpisode = VideoEpisodeSelection(
        episode: pending.$1,
        road: pending.$2,
      );
    }
    windowManager.addListener(this);
    // Window fullscreen can be changed outside this page through system chrome.
    videoPageController.isDesktopFullscreen();
    tabController = TabController(length: 2, vsync: this);
    // ⭐ 源失效自动换源：监听播放器线路加载失败信号
    _sourceFailedSubscription =
        playerController.playback.onSourceFailed.listen((_) {
      _autoSwitchSource();
    });
    // ⭐ 众包跳过：进入播放页拉取该番众包片头/片尾时长（未手动设置时自动生效）
    unawaited(SkipSegmentsService.fetchCrowd(videoPageController.bangumiItem.id));
    // ⭐ 夜间护眼：深夜自动降低屏幕亮度
    unawaited(_applyNightEye());
    // ⭐ 下一集预加载：接近结尾时提前解析下一集直链（设置可关）
    _preloadTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      try {
        final playback = playerController.playback;
        final pos = playback.currentPosition;
        final dur = playback.duration;
        if (dur > Duration.zero && pos >= dur * 0.75) {
          unawaited(videoPageController.preloadNextEpisode());
        }
      } catch (_) {}
    });
    observerController = GridObserverController(controller: scrollController);
    animation = AnimationController(
      duration: _sideTabAnimationDuration,
      vsync: this,
    );
    _rightOffsetAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: const Offset(0.0, 0.0),
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
    ));
    _maskOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.easeIn,
    ));

    playResume = GStorage.getSetting(SettingsKeys.playResume);
    disableAnimations =
        GStorage.getSetting(SettingsKeys.playerDisableAnimations);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitializePlayback) {
      return;
    }
    _didInitializePlayback = true;
    _initializePlayback();
  }

  void _initializePlayback() {
    if (videoPageController.isOfflineMode) {
      _initOfflineMode(playerController);
    } else {
      _initOnlineMode(playerController);
    }

    _syncChatSubscription =
        playerController.syncplay.chatStream.listen((event) {
      final localUsername =
          playerController.syncplay.syncplayController?.username ?? '';
      final String displayText = '${event.username}：${event.message}';

      if (playerController.danmaku.danmakuOn &&
          event.username != localUsername &&
          event.fromRemote) {
        playerController.danmaku.canvasController.addDanmaku(
          DanmakuContentItem(
            displayText,
            color: Colors.orange,
            isColorful: true,
            type: DanmakuItemType.bottom,
            extra: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    });
  }

  void _initOfflineMode(PlayerController playerController) {
    _showTabBodyImmediately(locateEpisode: false);
    final identity = videoPageController.currentHistoryIdentity;
    videoPageController.historyOffset = identity == null
        ? 0
        : videoPageController.getHistoryOffsetFor(identity);
    visibleRoad = videoPageController.selectedEpisode.road;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(_offlinePlayerInitDelay);
      if (!mounted) {
        return;
      }

      await changeEpisode(
        videoPageController.selectedEpisode.episode,
        currentRoad: videoPageController.selectedEpisode.road,
        offset: videoPageController.historyOffset,
      );
    });
  }

  void _initOnlineMode(PlayerController playerController) {
    videoPageController.historyOffset = 0;
    _showTabBodyImmediately(locateEpisode: false);

    var progress = historyController.lastWatching(
        videoPageController.bangumiItem,
        videoPageController.currentPlugin.name);
    if (progress != null) {
      if (videoPageController.roadList.length > progress.road) {
        if (videoPageController.roadList[progress.road].data.length >=
            progress.episode) {
          videoPageController.resetEpisodeState(
            episode: progress.episode,
            road: progress.road,
          );
          if (playResume) {
            videoPageController.historyOffset = progress.progress.inSeconds;
          }
        }
      }
    }
    visibleRoad = videoPageController.selectedEpisode.road;

    _logSubscription = videoPageController.logStream.listen((log) {
      if (mounted) {
        setState(() {
          webviewLogLines.add(log);
          if (webviewLogLines.length > 100) {
            webviewLogLines.removeAt(0);
          }
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      changeEpisode(videoPageController.selectedEpisode.episode,
          currentRoad: videoPageController.selectedEpisode.road,
          offset: videoPageController.historyOffset);
    });
  }

  @override
  /// ⭐ 夜间护眼：深夜(22-6点)自动降低屏幕亮度
  double? _nightEyeOriginalBrightness;

  Future<void> _applyNightEye() async {
    if (!GStorage.getSetting(SettingsKeys.nightEyeProtection)) return;
    final hour = DateTime.now().hour;
    if (hour >= 22 || hour < 6) {
      try {
        _nightEyeOriginalBrightness =
            await ScreenBrightnessPlatform.instance.application;
        await ScreenBrightnessPlatform.instance
            .setApplicationScreenBrightness(0.4);
      } catch (_) {}
    }
  }

  Future<void> _restoreNightEyeBrightness() async {
    if (_nightEyeOriginalBrightness != null) {
      try {
        await ScreenBrightnessPlatform.instance
            .setApplicationScreenBrightness(_nightEyeOriginalBrightness!);
      } catch (_) {}
      _nightEyeOriginalBrightness = null;
    }
  }

  void dispose() {
    _sourceFailedSubscription?.cancel();
    _sourceFailedSubscription = null;
    _preloadTimer?.cancel();
    _preloadTimer = null;
    unawaited(_restoreNightEyeBrightness());
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    try {
      scrollController.dispose();
    } catch (_) {}
    try {
      animation.dispose();
    } catch (_) {}
    try {
      _syncChatSubscription?.cancel();
    } catch (_) {}
    try {
      _logSubscription?.cancel();
    } catch (_) {}
    // Cancellation and log-stream teardown happen in VideoPageController's
    // own dispose when Modular releases the route scope.
    if (!isDesktop()) {
      try {
        ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
      } catch (_) {}
    }
    DisplayModeService.unlockScreenRotation();
    keyboardFocus.dispose();
    tabController.dispose();
    TimedShutdownService().cancel();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    _hideTabBodyImmediately();
    videoPageController.handleOnEnterFullScreen();
  }

  @override
  void onWindowLeaveFullScreen() {
    videoPageController.handleOnExitFullScreen();
  }

  void showDebugConsole() {
    setState(() {
      showDebugLog = true;
    });
  }

  void hideDebugConsole() {
    setState(() {
      showDebugLog = false;
    });
  }

  void switchDebugConsole() {
    setState(() {
      showDebugLog = !showDebugLog;
    });
  }

  void clearWebviewLog() {
    setState(() {
      webviewLogLines.clear();
    });
  }

  Future<void> changeEpisode(int episode,
      {int currentRoad = 0, int offset = 0}) async {
    if (!mounted) {
      return;
    }
    clearWebviewLog();
    hideDebugConsole();
    await videoPageController.changeEpisode(episode,
        currentRoad: currentRoad,
        offset: offset,
        playerController: playerController);
  }

  /// 该番上次看到的集数（来自历史记录）
  int _lastWatchedEpisode() {
    try {
      final id = videoPageController.bangumiItem.id;
      for (final h in HistoryRepository().getAllHistories()) {
        if (h.bangumiItem.id == id) return h.lastWatchEpisode;
      }
    } catch (_) {}
    return 0;
  }

  /// 源失效自动换源：切换到下一条线路重播当前集
  void _autoSwitchSource() {
    if (!mounted) return;
    final roadList = videoPageController.roadList;
    if (roadList.isEmpty) return;
    final currentEp = videoPageController.selectedEpisode.episode;
    final next = visibleRoad + 1;
    if (next < roadList.length) {
      setState(() {
        visibleRoad = next;
      });
      KazumiDialog.showToast(
          message: '线路「${roadList[next].name}」自动切换中...');
      changeEpisode(currentEp, currentRoad: next);
    } else {
      KazumiDialog.showToast(
          message: '所有线路均无法播放，请手动更换',
          showActionButton: true);
    }
  }

  void menuJumpToCurrentEpisode() {
    Future.delayed(const Duration(milliseconds: 20), () async {
      if (!mounted) {
        return;
      }
      await observerController.jumpTo(
          index: videoPageController.selectedEpisode.episode > 1
              ? videoPageController.selectedEpisode.episode - 1
              : videoPageController.selectedEpisode.episode);
    });
  }

  bool get _isSideTabLayout =>
      MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;

  bool get _canAnimateSideTab =>
      mounted && _isSideTabLayout && !disableAnimations;

  void _openTabBodyAnimated() {
    _setTabBodyVisible(true, animated: true);
    menuJumpToCurrentEpisode();
  }

  void _closeTabBodyAnimated() {
    _setTabBodyVisible(false, animated: true);
    keyboardFocus.requestFocus();
  }

  void _toggleTabBodyAnimated() {
    if (_tabBodyTargetVisible) {
      _closeTabBodyAnimated();
    } else {
      _openTabBodyAnimated();
    }
  }

  void _showTabBodyImmediately({bool locateEpisode = true}) {
    _setTabBodyVisible(true, animated: false);
    if (locateEpisode) {
      menuJumpToCurrentEpisode();
    }
  }

  void _hideTabBodyImmediately() {
    _setTabBodyVisible(false, animated: false);
  }

  void _setTabBodyVisible(bool visible, {required bool animated}) {
    _tabBodyTargetVisible = visible;
    final int animationRun = ++_tabBodyAnimationRun;

    if (visible) {
      if (!videoPageController.showTabBody) {
        animation.value = 0.0;
        videoPageController.showTabBody = true;
      }
      if (_canAnimateSideTab && animated) {
        animation.forward(from: animation.value);
      } else {
        animation.value = 1.0;
      }
      return;
    }

    if (!videoPageController.showTabBody) {
      animation.value = 0.0;
      return;
    }

    if (_canAnimateSideTab && animated && animation.value > 0.0) {
      animation.reverse().whenComplete(() {
        if (!mounted || animationRun != _tabBodyAnimationRun) {
          return;
        }
        videoPageController.showTabBody = false;
        animation.value = 0.0;
      });
      return;
    }

    videoPageController.showTabBody = false;
    animation.value = 0.0;
  }

  void _syncTabBodyAnimationAfterLayout() {
    if (!_tabBodyTargetVisible) {
      if (!videoPageController.showTabBody) {
        animation.value = 0.0;
      }
      return;
    }
    if (!videoPageController.showTabBody) {
      animation.value = 0.0;
      return;
    }
    if (!_isSideTabLayout || disableAnimations) {
      animation.value = 1.0;
      return;
    }
    if (animation.value == 0.0 && animation.status != AnimationStatus.reverse) {
      animation.forward();
    }
  }

  void onBackPressed(BuildContext context) async {
    if (KazumiDialog.observer.hasKazumiDialog) {
      KazumiDialog.dismiss();
      return;
    }
    if (videoPageController.isPip && isDesktop()) {
      PipUtils.exitDesktopPIPWindow();
      videoPageController.isPip = false;
      return;
    }
    if (videoPageController.isFullscreen && !isTablet()) {
      menuJumpToCurrentEpisode();
      await DisplayModeService.exitFullScreen();
      _hideTabBodyImmediately();
      videoPageController.isFullscreen = false;
      return;
    }
    if (videoPageController.isFullscreen) {
      await DisplayModeService.exitFullScreen();
      videoPageController.isFullscreen = false;
    }
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    playerController.beginShutdown();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  void pauseForTimedShutdown() {
    if (playerController.playback.playing) {
      playerController.pause();
    }
  }

  bool sendDanmaku(String msg) {
    keyboardFocus.requestFocus();
    if (playerController.danmaku.danDanmakus.isEmpty) {
      // ⭐ 自建弹幕开启时：即使其他弹幕还没加载（前几秒），也能发送到樱花服务器
      if (!GStorage.getSetting(SettingsKeys.customDanmakuEnabled)) {
        KazumiDialog.showToast(
          message: '当前剧集不支持弹幕发送的说',
        );
        return false;
      }
    }
    if (msg.isEmpty) {
      KazumiDialog.showToast(message: '弹幕内容为空');
      return false;
    } else if (msg.length > 100) {
      KazumiDialog.showToast(message: '弹幕内容过长');
      return false;
    }

    final destination = playerController.danmaku.danmakuDestination;

    if (destination == DanmakuDestination.chatRoom) {
      if (playerController.syncplay.syncplayRoom.isEmpty) {
        KazumiDialog.showToast(message: '你还没有加入一起看，无法发送聊天室弹幕');
        return false;
      }

      final sender =
          playerController.syncplay.syncplayController?.username ?? '我';
      final String displayText = '$sender：$msg';

      playerController.danmaku.canvasController.addDanmaku(
        DanmakuContentItem(
          displayText,
          color: Colors.orange,
          isColorful: true,
          type: DanmakuItemType.bottom,
          extra: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      unawaited(playerController.sendSyncPlayChatMessage(msg));
    } else {
      // The remote danmaku provider does not expose a send API here; render the
      // local echo so the user still sees their message immediately.
      playerController.danmaku.canvasController
          .addDanmaku(DanmakuContentItem(msg, selfSend: true));

      // ⭐ 自建弹幕：同步发送到自己的服务器（设置开启时；服务端过滤网址 + 待审核）
      if (GStorage.getSetting(SettingsKeys.customDanmakuEnabled)) {
        unawaited(_sendToCustomDanmakuServer(msg));
      }
    }

    return true;
  }

  /// ⭐ 最近一次发送弹幕选择的位置（1=滚动 5=置顶 4=置底）
  int _lastDanmakuType = 1;

  /// 发送弹幕到自建服务器
  Future<void> _sendToCustomDanmakuServer(String msg) async {
    try {
      final bangumiId = videoPageController.bangumiItem.id;
      final ep = videoPageController.playingEpisode?.episode ??
          videoPageController.selectedEpisode.episode;
      final timeMs =
          playerController.playback.currentPosition.inMilliseconds;
      final error = await CustomDanmakuApi.send(
        bangumiId: bangumiId,
        episode: ep,
        timeMs: timeMs,
        text: msg,
        sender: '',
        type: _lastDanmakuType,
      );
      if (error != null) {
        // 静默：失败不上报弹窗，本地已回显
        KazumiLogger().w('CustomDanmaku: $error');
      }
    } catch (e) {
      KazumiLogger().e('CustomDanmaku: 发送异常', error: e);
    }
  }

  Future<void> showMobileDanmakuInput() async {
    final result = await showMobileDanmakuInputSheet(context);

    if (!mounted || result == null) {
      return;
    }
    _lastDanmakuType = result.type; // 记住本次选择的位置（1=滚动 5=置顶 4=置底）
    await showDanmakuDestinationPickerAndSend(result.text);
  }

  Future<bool> showDanmakuDestinationPickerAndSend(String msg) async {
    if (msg.trim().isEmpty) {
      KazumiDialog.showToast(message: '弹幕内容为空');
      return false;
    }

    final DanmakuDestination? result =
        await showAdaptiveBottomSheet<DanmakuDestination>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MaterialBottomSheetHeader(
                title: '发送弹幕至',
                description: '选择这条弹幕的发送位置',
                onClose: () => Navigator.of(context).pop(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MaterialBottomSheetGroup(
                  title: '发送位置',
                  children: [
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      leading: const Icon(Icons.groups_rounded),
                      title: const Text('发送到聊天室'),
                      subtitle: const Text('同步观看成员均可看到'),
                      onTap: () => Navigator.of(context)
                          .pop(DanmakuDestination.chatRoom),
                    ),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      leading: const Icon(Icons.cloud_upload_rounded),
                      title: const Text('发送到远程弹幕库'),
                      subtitle: const Text('作为视频弹幕发送'),
                      onTap: () => Navigator.of(context)
                          .pop(DanmakuDestination.remoteDanmaku),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == null || !mounted) {
      return false;
    }

    setState(() {});
    playerController.danmaku.danmakuDestination = result;
    return sendDanmaku(msg);
  }

  @override
  Widget build(BuildContext context) {
    final bool isLandscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncTabBodyAnimationAfterLayout();
    });
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        onBackPressed(context);
      },
      child: OrientationBuilder(builder: (context, orientation) {
        if (!isDesktop()) {
          if (orientation == Orientation.landscape &&
              !videoPageController.isFullscreen) {
            _hideTabBodyImmediately();
            videoPageController.enterFullScreen();
          } else if (orientation == Orientation.portrait &&
              videoPageController.isFullscreen) {
            videoPageController.exitFullScreen();
            _showTabBodyImmediately();
          }
        }
        return Observer(builder: (context) {
          return Scaffold(
            appBar: null,
            body: SafeArea(
                top: !videoPageController.isFullscreen,
                // set iOS and Android navigation bar to immersive
                bottom: false,
                left: !videoPageController.isFullscreen,
                right: !videoPageController.isFullscreen,
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    Column(
                      children: [
                        Flexible(
                          flex: isLandscape ? 1 : 0,
                          child: Container(
                            color: Colors.black,
                            height: isLandscape
                                ? MediaQuery.sizeOf(context).height
                                : MediaQuery.sizeOf(context).width * 9 / 16,
                            width: MediaQuery.sizeOf(context).width,
                            child: Focus(
                              focusNode: keyboardFocus,
                              autofocus: true,
                              child: playerBody,
                            ),
                          ),
                        ),
                        if (!isLandscape) Expanded(child: tabBody),
                      ],
                    ),
                    if (isLandscape && videoPageController.showTabBody) ...[
                      if (disableAnimations) ...[
                        sideTabMask,
                        sideTabBody,
                      ] else ...[
                        FadeTransition(
                          opacity: _maskOpacityAnimation,
                          child: sideTabMask,
                        ),
                        SlideTransition(
                          position: _rightOffsetAnimation,
                          child: sideTabBody,
                        ),
                      ],
                    ],
                  ],
                )),
          );
        });
      }),
    );
  }

  Widget get sideTabBody {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height,
      width: (!isDesktop() && !isTablet())
          ? MediaQuery.sizeOf(context).height
          : (MediaQuery.sizeOf(context).width / 3 > 420
              ? 420
              : MediaQuery.sizeOf(context).width / 3),
      child: Container(
        color: Theme.of(context).canvasColor,
        child: GridViewObserver(
          controller: observerController,
          child: (isDesktop() || isTablet())
              ? tabBody
              : Column(
                  children: [
                    menuBar,
                    menuBody,
                  ],
                ),
        ),
      ),
    );
  }

  Widget get sideTabMask {
    return GestureDetector(
      onTap: _closeTabBodyAnimated,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.black.withValues(alpha: 0.5),
              Colors.transparent,
            ],
          ),
        ),
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  /// 把当前播放的集加入连播队列（"稍后看"）
  Future<void> _addCurrentToPlayQueue() async {
    try {
      final selection = videoPageController.selectedEpisode;
      final item = PlayQueueItem(
        bangumiItem: videoPageController.bangumiItem,
        plugin: videoPageController.currentPlugin,
        title: videoPageController.title,
        src: videoPageController.src,
        roads: List.from(videoPageController.roadList),
        episode: selection.episode,
        road: selection.road,
        addedTime: DateTime.now(),
      );
      final added = await PlayQueueService.instance.add(item);
      if (!mounted) return;
      KazumiDialog.showToast(
        message: added
            ? '✅ 已加入连播队列（共 ${PlayQueueService.instance.length} 项）'
            : '该集已在队列中',
      );
    } catch (e) {
      KazumiLogger().e('PlayQueue: add failed', error: e);
    }
  }

  /// 打开连播队列页
  void _openPlayQueuePage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayQueuePage()),
    );
  }

  /// 最后一集播完：同步判断队列是否有下一项，有则异步接播（跨番剧连播）
  /// 返回 true 表示已接管播放（不再标记"看过"）
  bool _tryPlayNextFromQueue() {
    if (PlayQueueService.instance.length == 0) return false;
    unawaited(_playNextFromQueue());
    return true;
  }

  Future<void> _playNextFromQueue() async {
    final next = await PlayQueueService.instance.takeNext();
    if (next == null || !mounted) return;
    VideoPageController.pendingQueueEpisode = (next.episode, next.road);
    await Navigator.of(context).pushNamed(
      '/video/',
      arguments: OnlineVideoPlaybackArgs(
        bangumiItem: next.bangumiItem,
        plugin: next.plugin,
        title: next.title,
        src: next.src,
        roads: next.roads,
      ),
    );
  }

  Widget get playerBody {
    final bool playerLoading = playerController.playback.loading;
    return Stack(
      children: [
        Positioned.fill(
          child: Stack(
            children: [
              if (videoPageController.loading ||
                  playerLoading ||
                  videoPageController.errorMessage != null)
                Container(
                  color: Colors.black,
                  child: Observer(builder: (context) {
                    return Center(
                      child: videoPageController.errorMessage != null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline,
                                    color: Theme.of(context).colorScheme.error,
                                    size: 48),
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 32),
                                  child: Text(
                                    videoPageController.errorMessage!,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 16),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .tertiaryContainer),
                                const SizedBox(height: 10),
                                Text(
                                  videoPageController.loading
                                      ? '视频资源解析中'
                                      : '视频资源解析成功, 播放器加载中',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                    );
                  }),
                ),
              Visibility(
                visible: (videoPageController.loading || playerLoading) &&
                    showDebugLog,
                child: Container(
                  color: Colors.black,
                  child: Align(
                    alignment: Alignment.center,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: webviewLogLines.length,
                      itemBuilder: (context, index) {
                        return Text(
                          webviewLogLines.isEmpty ? '' : webviewLogLines[index],
                          style: const TextStyle(
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                ),
              ),
              Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: EmbeddedNativeControlArea(
                      requireOffset: !videoPageController.isFullscreen,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
                            onPressed: () => onBackPressed(context),
                          ),
                          const Expanded(
                              child: dtb.DragToMoveArea(
                                  child: SizedBox(height: 40))),
                          IconButton(
                            icon: const Icon(Icons.refresh_outlined,
                                color: Colors.white),
                            onPressed: () {
                              changeEpisode(
                                  videoPageController.selectedEpisode.episode,
                                  currentRoad:
                                      videoPageController.selectedEpisode.road);
                            },
                          ),
                          Visibility(
                            visible: MediaQuery.sizeOf(context).width >
                                MediaQuery.sizeOf(context).height,
                            child: IconButton(
                              onPressed: () {
                                _toggleTabBodyAnimated();
                              },
                              icon: Icon(
                                _tabBodyTargetVisible
                                    ? Icons.menu_open
                                    : Icons.menu_open_outlined,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                                showDebugLog
                                    ? Icons.bug_report
                                    : Icons.bug_report_outlined,
                                color: Colors.white),
                            onPressed: () {
                              switchDebugConsole();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: playerController.playback.loading
              ? Container()
              : PlayerItem(
                  playerController: playerController,
                  videoPageController: videoPageController,
                  toggleMenu: _toggleTabBodyAnimated,
                  showMenuImmediately: _showTabBodyImmediately,
                  hideMenuImmediately: _hideTabBodyImmediately,
                  changeEpisode: changeEpisode,
                  onBackPressed: onBackPressed,
                  keyboardFocus: keyboardFocus,
                  sendDanmaku: sendDanmaku,
                  disableAnimations: disableAnimations,
                  showDanmakuDestinationPickerAndSend:
                      showDanmakuDestinationPickerAndSend,
                  pauseForTimedShutdown: pauseForTimedShutdown,
                  onAddToPlayQueue: _addCurrentToPlayQueue,
                  onOpenPlayQueue: _openPlayQueuePage,
                  onPlayNextFromQueue: _tryPlayNextFromQueue,
                ),
        ),
      ],
    );
  }

  Widget get menuBar {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(' 合集 '),
          Expanded(
            child: Text(
              videoPageController.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(width: 10),
          MenuAnchor(
            consumeOutsideTap: true,
            builder: (_, MenuController controller, __) {
              return SizedBox(
                height: 34,
                child: TextButton(
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(EdgeInsets.zero),
                  ),
                  onPressed: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  child: Text(
                    visibleRoad >= 0 &&
                            visibleRoad < videoPageController.roadList.length
                        ? '${videoPageController.roadList[visibleRoad].name} '
                        : '播放线路${visibleRoad + 1} ',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              );
            },
            menuChildren: List<MenuItemButton>.generate(
              videoPageController.roadList.length,
              (int i) => MenuItemButton(
                onPressed: () {
                  setState(() {
                    visibleRoad = i;
                  });
                },
                child: Container(
                  height: 48,
                  constraints: BoxConstraints(minWidth: 112),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      videoPageController.roadList[i].name,
                      style: TextStyle(
                        color: i == visibleRoad
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  DownloadEpisode? _getEpisodeFromRecords(
      int episodeNumber, String episodePageUrl) {
    final bangumiId = videoPageController.bangumiItem.id;
    final pluginName = videoPageController.currentPlugin.name;

    for (final record in downloadController.records) {
      if (record.bangumiId == bangumiId && record.pluginName == pluginName) {
        if (episodePageUrl.isNotEmpty) {
          for (final episode in record.episodes.values) {
            if (episode.episodePageUrl == episodePageUrl) {
              return episode;
            }
          }
        }
        return record.episodes[episodeNumber];
      }
    }
    return null;
  }

  Widget _buildDownloadStatusIcon(int episodeNumber, String episodePageUrl) {
    if (videoPageController.isOfflineMode) return const SizedBox.shrink();
    final episode = _getEpisodeFromRecords(episodeNumber, episodePageUrl);
    if (episode == null) return const SizedBox.shrink();
    switch (episode.status) {
      case DownloadStatus.completed:
        return Icon(Icons.offline_pin,
            size: 16, color: Theme.of(context).colorScheme.primary);
      case DownloadStatus.downloading:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            value: episode.progressPercent,
            strokeWidth: 2,
          ),
        );
      case DownloadStatus.failed:
        return Icon(Icons.error_outline,
            size: 16, color: Theme.of(context).colorScheme.error);
      case DownloadStatus.paused:
        return Icon(Icons.pause_circle_outline,
            size: 16, color: Theme.of(context).colorScheme.outline);
      case DownloadStatus.pending:
      case DownloadStatus.resolving:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget get menuBody {
    return Observer(
      builder: (context) {
        var cardList = <Widget>[];
        if (visibleRoad >= 0 &&
            visibleRoad < videoPageController.roadList.length) {
          final road = videoPageController.roadList[visibleRoad];
          int count = 1;
          for (var urlItem in road.data) {
            int count0 = count;
            final episodeName = count0 - 1 < road.identifier.length
                ? road.identifier[count0 - 1]
                : '第$count0集';
            cardList.add(Container(
              margin: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: Theme.of(context).colorScheme.onInverseSurface,
                borderRadius: BorderRadius.circular(6),
                clipBehavior: Clip.hardEdge,
                child: InkWell(
                  onTap: () async {
                    if (count0 == videoPageController.selectedEpisode.episode &&
                        videoPageController.selectedEpisode.road ==
                            visibleRoad) {
                      return;
                    }
                    KazumiLogger()
                        .i('VideoPageController: video URL is $urlItem');
                    _closeTabBodyAnimated();
                    changeEpisode(count0, currentRoad: visibleRoad);
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: [
                            if (count0 ==
                                    (videoPageController
                                        .selectedEpisode.episode) &&
                                visibleRoad ==
                                    videoPageController
                                        .selectedEpisode.road) ...<Widget>[
                              Image.asset(
                                'assets/images/playing.gif',
                                color: Theme.of(context).colorScheme.primary,
                                height: 12,
                              ),
                              const SizedBox(width: 6)
                            ],
                            Expanded(
                                child: Text(
                              episodeName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: (count0 ==
                                              videoPageController
                                                  .selectedEpisode.episode &&
                                          visibleRoad ==
                                              videoPageController
                                                  .selectedEpisode.road)
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                            )),
                            _buildDownloadStatusIcon(count0, urlItem),
                            const SizedBox(width: 2),
                          ],
                        ),
                        const SizedBox(height: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ));
            count++;
          }
        }
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 0, right: 8, left: 8),
            child: GridView.builder(
              scrollDirection: Axis.vertical,
              controller: scrollController,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 5,
                mainAxisExtent: 70,
              ),
              itemCount: cardList.length,
              itemBuilder: (context, index) {
                return cardList[index];
              },
            ),
          ),
        );
      },
    );
  }

  Widget get tabBody {
    final bool danmakuOn = playerController.danmaku.danmakuOn;
    final int episodeNum = videoPageController.commentsEpisode;

    return Container(
      color: Theme.of(context).canvasColor,
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TabBar(
                  controller: tabController,
                  dividerHeight: 0,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding:
                      const EdgeInsetsDirectional.only(start: 30, end: 30),
                  onTap: (index) {
                    if (index == 0) {
                      menuJumpToCurrentEpisode();
                    }
                  },
                  tabs: const [
                    Tab(text: '选集'),
                    Tab(text: '评论'),
                  ],
                ),
                if (MediaQuery.sizeOf(context).width <=
                    MediaQuery.sizeOf(context).height) ...[
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: danmakuOn
                            ? Theme.of(context).hintColor
                            : Theme.of(context).disabledColor,
                        width: 0.5,
                      ),
                    ),
                    child: GestureDetector(
                      onTap: () {
                        if (danmakuOn && !videoPageController.loading) {
                          showMobileDanmakuInput();
                        } else if (videoPageController.loading) {
                          KazumiDialog.showToast(message: '请等待视频加载完成');
                        } else {
                          KazumiDialog.showToast(message: '请先打开弹幕');
                        }
                      },
                      child: Row(
                        children: [
                          Text(
                            danmakuOn ? '  点我发弹幕  ' : '  已关闭弹幕  ',
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              color: danmakuOn
                                  ? Theme.of(context).hintColor
                                  : Theme.of(context).disabledColor,
                            ),
                          ),
                          if (danmakuOn)
                            Icon(
                              Icons.send_rounded,
                              size: 20,
                              color: Theme.of(context).hintColor,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
              ],
            ),
            Divider(height: isDesktop() ? 0.5 : 0.2),
            Expanded(
              child: TabBarView(
                controller: tabController,
                children: [
                  Stack(
                    children: [
                      GridViewObserver(
                        controller: observerController,
                        child: Column(
                          children: [
                            // ⭐ 下一集检测：上次看到第X集，第X+1集可看
                            Builder(builder: (context) {
                              final lastEp = _lastWatchedEpisode();
                              final totalEp =
                                  visibleRoad >= 0 &&
                                          visibleRoad <
                                              videoPageController.roadList.length
                                      ? videoPageController
                                          .roadList[visibleRoad].data.length
                                      : 0;
                              if (lastEp <= 0 || lastEp >= totalEp) {
                                return const SizedBox.shrink();
                              }
                              return Material(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: InkWell(
                                  onTap: () => changeEpisode(
                                    lastEp + 1,
                                    currentRoad: visibleRoad,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.play_circle_fill,
                                          size: 20,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '上次看到第 $lastEp 集 · 第 ${lastEp + 1} 集可看，点击继续',
                                            style: const TextStyle(
                                                fontSize: 13),
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right,
                                            size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                            menuBar,
                            menuBody,
                          ],
                        ),
                      ),
                      if (!videoPageController.isOfflineMode)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: FloatingActionButton(
                            child: const Icon(Icons.download_rounded),
                            onPressed: () {
                              showAdaptiveBottomSheet<void>(
                                context: context,
                                builder: (context) => DownloadEpisodeSheet(
                                  road: visibleRoad,
                                  videoPageController: videoPageController,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  EpisodeCommentsSheet(
                    episode: episodeNum,
                    selection: videoPageController.selectedEpisode,
                    videoPageController: videoPageController,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

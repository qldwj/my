enum SettingGroup {
  player,
  danmaku,
  theme,
  interface,
  proxy,
  webdav,
  download,
  bangumi,
  collect,
  sync,
  update,
  notice,      // 新增公告分组
  misc,
}

class SettingContext {
  const SettingContext({this.compactLayout = false});

  final bool compactLayout;
}

class SettingKey<T> {
  const SettingKey(
    this.name,
    this.defaultValue, {
    required this.group,
    this.defaultResolver,
  });

  final String name;
  final T defaultValue;
  final SettingGroup group;
  final T Function(SettingContext context)? defaultResolver;

  T resolveDefault(SettingContext context) {
    return defaultResolver?.call(context) ?? defaultValue;
  }
}

class SettingsKeys {
  static const hAenable = SettingKey<bool>(
    _SettingBoxKey.hAenable,
    true,
    group: SettingGroup.player,
  );
  static const autoSwitchSource = SettingKey<bool>(
    _SettingBoxKey.autoSwitchSource,
    true,
    group: SettingGroup.player,
  );
  static const skipOpDurations = SettingKey<String>(
    _SettingBoxKey.skipOpDurations,
    '{}',
    group: SettingGroup.player,
  );
  static const skipEdDurations = SettingKey<String>(
    _SettingBoxKey.skipEdDurations,
    '{}',
    group: SettingGroup.player,
  );
  static const skipOpDefaultSeconds = SettingKey<int>(
    _SettingBoxKey.skipOpDefaultSeconds,
    60,
    group: SettingGroup.player,
  );
  static const skipEdDefaultSeconds = SettingKey<int>(
    _SettingBoxKey.skipEdDefaultSeconds,
    60,
    group: SettingGroup.player,
  );
  static const hardwareDecoder = SettingKey<String>(
    _SettingBoxKey.hardwareDecoder,
    'auto-safe',
    group: SettingGroup.player,
  );
  static const searchEnhanceEnable = SettingKey<bool>(
    _SettingBoxKey.searchEnhanceEnable,
    true,
    group: SettingGroup.misc,
  );
  static const autoUpdate = SettingKey<bool>(
    _SettingBoxKey.autoUpdate,
    true,
    group: SettingGroup.update,
  );
  static const checkPluginUpdateOnStartup = SettingKey<bool>(
    'checkPluginUpdateOnStartup',
    true,
    group: SettingGroup.update,
  );
  static const alwaysOntop = SettingKey<bool>(
    _SettingBoxKey.alwaysOntop,
    false,
    group: SettingGroup.misc,
  );
  static const defaultPlaySpeed = SettingKey<double>(
    _SettingBoxKey.defaultPlaySpeed,
    1.0,
    group: SettingGroup.player,
  );
  static const defaultShortcutForwardPlaySpeed = SettingKey<double>(
    _SettingBoxKey.defaultShortcutForwardPlaySpeed,
    2.0,
    group: SettingGroup.player,
  );
  static const defaultAspectRatioType = SettingKey<int>(
    _SettingBoxKey.defaultAspectRatioType,
    1,
    group: SettingGroup.player,
  );
  static const buttonSkipTime = SettingKey<int>(
    _SettingBoxKey.buttonSkipTime,
    80,
    group: SettingGroup.player,
  );
  static const arrowKeySkipTime = SettingKey<int>(
    _SettingBoxKey.arrowKeySkipTime,
    10,
    group: SettingGroup.player,
  );
  static const danmakuEnhance = SettingKey<bool>(
    _SettingBoxKey.danmakuEnhance,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBorder = SettingKey<bool>(
    _SettingBoxKey.danmakuBorder,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBorderSize = SettingKey<double>(
    _SettingBoxKey.danmakuBorderSize,
    1.5,
    group: SettingGroup.danmaku,
  );
  static const danmakuOpacity = SettingKey<double>(
    _SettingBoxKey.danmakuOpacity,
    1.0,
    group: SettingGroup.danmaku,
  );
  static final danmakuFontSize = SettingKey<double>(
    _SettingBoxKey.danmakuFontSize,
    25.0,
    group: SettingGroup.danmaku,
    defaultResolver: (context) => context.compactLayout ? 16.0 : 25.0,
  );
  static const danmakuTop = SettingKey<bool>(
    _SettingBoxKey.danmakuTop,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuScroll = SettingKey<bool>(
    _SettingBoxKey.danmakuScroll,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBottom = SettingKey<bool>(
    _SettingBoxKey.danmakuBottom,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuMassive = SettingKey<bool>(
    _SettingBoxKey.danmakuMassive,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuDeduplication = SettingKey<bool>(
    _SettingBoxKey.danmakuDeduplication,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuArea = SettingKey<double>(
    _SettingBoxKey.danmakuArea,
    1.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuColor = SettingKey<bool>(
    _SettingBoxKey.danmakuColor,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuDuration = SettingKey<double>(
    _SettingBoxKey.danmakuDuration,
    8.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuLineHeight = SettingKey<double>(
    _SettingBoxKey.danmakuLineHeight,
    1.6,
    group: SettingGroup.danmaku,
  );
  static const danmakuTimeOffset = SettingKey<double>(
    _SettingBoxKey.danmakuTimeOffset,
    0.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuEnabledByDefault = SettingKey<bool>(
    _SettingBoxKey.danmakuEnabledByDefault,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuBiliBiliSource = SettingKey<bool>(
    _SettingBoxKey.danmakuBiliBiliSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuGamerSource = SettingKey<bool>(
    _SettingBoxKey.danmakuGamerSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuDanDanSource = SettingKey<bool>(
    _SettingBoxKey.danmakuDanDanSource,
    true,
    group: SettingGroup.danmaku,
  );
  /// 自建弹幕（发送到自己的服务器 + 显示已审核弹幕）
  static const customDanmakuEnabled = SettingKey<bool>(
    _SettingBoxKey.customDanmakuEnabled,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuFontWeight = SettingKey<int>(
    _SettingBoxKey.danmakuFontWeight,
    4,
    group: SettingGroup.danmaku,
  );
  static const danmakuFollowSpeed = SettingKey<bool>(
    _SettingBoxKey.danmakuFollowSpeed,
    true,
    group: SettingGroup.danmaku,
  );
  static const themeMode = SettingKey<String>(
    _SettingBoxKey.themeMode,
    'system',
    group: SettingGroup.theme,
  );
  static const themeColor = SettingKey<String>(
    _SettingBoxKey.themeColor,
    'default',
    group: SettingGroup.theme,
  );
  static const privateMode = SettingKey<bool>(
    _SettingBoxKey.privateMode,
    false,
    group: SettingGroup.player,
  );
  static const autoPlay = SettingKey<bool>(
    _SettingBoxKey.autoPlay,
    true,
    group: SettingGroup.player,
  );
  static const autoPlayNext = SettingKey<bool>(
    _SettingBoxKey.autoPlayNext,
    true,
    group: SettingGroup.player,
  );
  /// 预加载下一集（接近结尾时提前解析下一集视频地址，连播秒开；可关闭避免影响当前集）
  static const preloadNextEpisode = SettingKey<bool>(
    _SettingBoxKey.preloadNextEpisode,
    true,
    group: SettingGroup.player,
  );
  /// 夜间护眼：深夜(22:00-06:00)播放页自动降低屏幕亮度
  static const nightEyeProtection = SettingKey<bool>(
    _SettingBoxKey.nightEyeProtection,
    false,
    group: SettingGroup.player,
  );
  /// 自动选择视频源：点击开始观看后自动用第一个可用的源播放，无需手动选择
  static const autoSelectSource = SettingKey<bool>(
    _SettingBoxKey.autoSelectSource,
    true,
    group: SettingGroup.player,
  );
  static const playResume = SettingKey<bool>(
    _SettingBoxKey.playResume,
    true,
    group: SettingGroup.player,
  );
  static const showPlayerError = SettingKey<bool>(
    _SettingBoxKey.showPlayerError,
    true,
    group: SettingGroup.player,
  );
  static const oledEnhance = SettingKey<bool>(
    _SettingBoxKey.oledEnhance,
    false,
    group: SettingGroup.theme,
  );
  static const displayMode = SettingKey<String?>(
    _SettingBoxKey.displayMode,
    null,
    group: SettingGroup.interface,
  );
  static const enableGitProxy = SettingKey<bool>(
    _SettingBoxKey.enableGitProxy,
    true,
    group: SettingGroup.proxy,
  );
  static const enableBangumiProxy = SettingKey<bool>(
    _SettingBoxKey.enableBangumiProxy,
    true,
    group: SettingGroup.proxy,
  );
  static const enableSystemProxy = SettingKey<bool>(
    _SettingBoxKey.enableSystemProxy,
    false,
    group: SettingGroup.proxy,
  );
  static const defaultStartupPage = SettingKey<String>(
    _SettingBoxKey.defaultStartupPage,
    '/tab/popular/',
    group: SettingGroup.interface,
  );
  static const isWideScreen = SettingKey<bool>(
    _SettingBoxKey.isWideScreen,
    false,
    group: SettingGroup.interface,
  );
  static const webDavEnable = SettingKey<bool>(
    _SettingBoxKey.webDavEnable,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavEnableHistory = SettingKey<bool>(
    _SettingBoxKey.webDavEnableHistory,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavEnableCollect = SettingKey<bool>(
    _SettingBoxKey.webDavEnableCollect,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavURL = SettingKey<String>(
    _SettingBoxKey.webDavURL,
    '',
    group: SettingGroup.webdav,
  );
  static const webDavUsername = SettingKey<String>(
    _SettingBoxKey.webDavUsername,
    '',
    group: SettingGroup.webdav,
  );
  static const webDavPassword = SettingKey<String>(
    _SettingBoxKey.webDavPassword,
    '',
    group: SettingGroup.webdav,
  );
  static const lowMemoryMode = SettingKey<bool>(
    _SettingBoxKey.lowMemoryMode,
    false,
    group: SettingGroup.player,
  );
  static const showWindowButton = SettingKey<bool>(
    _SettingBoxKey.showWindowButton,
    false,
    group: SettingGroup.theme,
  );
  static const useDynamicColor = SettingKey<bool>(
    _SettingBoxKey.useDynamicColor,
    false,
    group: SettingGroup.theme,
  );
  static const exitBehavior = SettingKey<int>(
    _SettingBoxKey.exitBehavior,
    2,
    group: SettingGroup.interface,
  );
  static const playerDebugMode = SettingKey<bool>(
    _SettingBoxKey.playerDebugMode,
    false,
    group: SettingGroup.player,
  );
  static const syncPlayEndPoint = SettingKey<String>(
    _SettingBoxKey.syncPlayEndPoint,
    '127.0.0.1:8999',
    group: SettingGroup.player,
  );
  static const androidEnableOpenSLES = SettingKey<bool>(
    _SettingBoxKey.androidEnableOpenSLES,
    true,
    group: SettingGroup.player,
  );
  static const androidVideoRenderer = SettingKey<String>(
    _SettingBoxKey.androidVideoRenderer,
    'auto',
    group: SettingGroup.player,
  );
  static const androidAutoEnterPIP = SettingKey<bool>(
    _SettingBoxKey.androidAutoEnterPIP,
    false,
    group: SettingGroup.player,
  );
  static const defaultSuperResolutionMode = SettingKey<int>(
    _SettingBoxKey.defaultSuperResolutionMode,
    1,
    group: SettingGroup.player,
  );
  static const disableSuperResolutionWarning = SettingKey<bool>(
    _SettingBoxKey.disableSuperResolutionWarning,
    false,
    group: SettingGroup.player,
  );
  static const playerDisableAnimations = SettingKey<bool>(
    _SettingBoxKey.playerDisableAnimations,
    false,
    group: SettingGroup.player,
  );
  static const playerLogLevel = SettingKey<int>(
    _SettingBoxKey.playerLogLevel,
    2,
    group: SettingGroup.player,
  );
  static const timelineNotShowAbandonedBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineNotShowAbandonedBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const timelineNotShowWatchedBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineNotShowWatchedBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const timelineOnlyShowWatchingBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineOnlyShowWatchingBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const useSystemFont = SettingKey<bool>(
    _SettingBoxKey.useSystemFont,
    false,
    group: SettingGroup.interface,
  );
  /// 自定义字体文件路径（选择 .ttf/.otf 后保存，重启后加载）
  static const customFontPath = SettingKey<String>(
    _SettingBoxKey.customFontPath,
    '',
    group: SettingGroup.interface,
  );
  static const forceAdBlocker = SettingKey<bool>(
    _SettingBoxKey.forceAdBlocker,
    false,
    group: SettingGroup.player,
  );
  static const backgroundPlayback = SettingKey<bool>(
    _SettingBoxKey.backgroundPlayback,
    false,
    group: SettingGroup.player,
  );
  static const proxyEnable = SettingKey<bool>(
    _SettingBoxKey.proxyEnable,
    false,
    group: SettingGroup.proxy,
  );
  static const proxyConfigured = SettingKey<bool>(
    _SettingBoxKey.proxyConfigured,
    false,
    group: SettingGroup.proxy,
  );
  static const proxyUrl = SettingKey<String>(
    _SettingBoxKey.proxyUrl,
    '',
    group: SettingGroup.proxy,
  );
  static const proxyTestUrl = SettingKey<String>(
    _SettingBoxKey.proxyTestUrl,
    '',
    group: SettingGroup.proxy,
  );
  static const showRating = SettingKey<bool>(
    _SettingBoxKey.showRating,
    true,
    group: SettingGroup.interface,
  );
  static const showAnimeCounter = SettingKey<bool>(
    _SettingBoxKey.showAnimeCounter,
    false,
    group: SettingGroup.interface,
  );
  static const downloadParallelEpisodes = SettingKey<int>(
    _SettingBoxKey.downloadParallelEpisodes,
    2,
    group: SettingGroup.download,
  );
  static const downloadParallelSegments = SettingKey<int>(
    _SettingBoxKey.downloadParallelSegments,
    3,
    group: SettingGroup.download,
  );
  static const downloadDanmaku = SettingKey<bool>(
    _SettingBoxKey.downloadDanmaku,
    true,
    group: SettingGroup.download,
  );
  static const downloadDirectory = SettingKey<String>(
    _SettingBoxKey.downloadDirectory,
    '',
    group: SettingGroup.download,
  );
  static const downloadDirectoryBookmark = SettingKey<String>(
    'downloadDirectoryBookmark',
    '',
    group: SettingGroup.download,
  );
  static const shortcutDialogShown = SettingKey<bool>(
    _SettingBoxKey.shortcutDialogShown,
    false,
    group: SettingGroup.misc,
  );
  static const bangumiSyncEnable = SettingKey<bool>(
    _SettingBoxKey.bangumiSyncEnable,
    false,
    group: SettingGroup.bangumi,
  );
  static const bangumiAccessToken = SettingKey<String>(
    _SettingBoxKey.bangumiAccessToken,
    '',
    group: SettingGroup.bangumi,
  );
  static const bangumiSyncPriority = SettingKey<int>(
    _SettingBoxKey.bangumiSyncPriority,
    0,
    group: SettingGroup.bangumi,
  );
  static const bangumiImmediateSyncToastEnable = SettingKey<bool>(
    _SettingBoxKey.bangumiImmediateSyncToastEnable,
    true,
    group: SettingGroup.bangumi,
  );
  static const brightnessVolumeGesture = SettingKey<bool>(
    _SettingBoxKey.brightnessVolumeGesture,
    true,
    group: SettingGroup.player,
  );
  static const historySyncDeviceId = SettingKey<String>(
    _SettingBoxKey.historySyncDeviceId,
    '',
    group: SettingGroup.sync,
  );
  static const historySyncSequence = SettingKey<int>(
    _SettingBoxKey.historySyncSequence,
    0,
    group: SettingGroup.sync,
  );
  static const historySyncSnapshotInitialized = SettingKey<bool>(
    _SettingBoxKey.historySyncSnapshotInitialized,
    false,
    group: SettingGroup.sync,
  );
  static const playerControllerLayerDisappearTime = SettingKey<int>(
    'playerControllerLayerDisappearTime',
    4000,
    group: SettingGroup.player,
  );
  static const defaultVolume = SettingKey<double>(
    'defaultVolume',
    100.0,
    group: SettingGroup.player,
  );
  static const playerMuted = SettingKey<bool>(
    'playerMuted',
    false,
    group: SettingGroup.player,
  );
  static const showLastWatchCard = SettingKey<bool>(
    'showLastWatchCard',
    true,
    group: SettingGroup.player,
  );
  static const enableDesktopWidget = SettingKey<bool>(
    'enableDesktopWidget',
    true,
    group: SettingGroup.theme,
  );
  static const enableUpdateNotification = SettingKey<bool>(
    'enableUpdateNotification',
    true,
    group: SettingGroup.theme,
  );
  static const updateChannel = SettingKey<String>(
    'updateChannel',
    'stable',
    group: SettingGroup.update,
  );
  static const animekoRuleLastCheck = SettingKey<int>(
    'animekoRuleLastCheck',
    0,
    group: SettingGroup.update,
  );
  static const animekoUpdateInterval = SettingKey<int>(
    'animekoUpdateInterval',
    30,
    group: SettingGroup.update,
  );
  static const kazumiToken = SettingKey<String>(
    'kazumiToken',
    '',
    group: SettingGroup.sync,
  );
  static const kazumiSyncEnable = SettingKey<bool>(
    'kazumiSyncEnable',
    true,
    group: SettingGroup.sync,
  );
  static const weeklyWatchGoal = SettingKey<int>(
    _SettingBoxKey.weeklyWatchGoal,
    0,
    group: SettingGroup.misc,
  );
  static const kazumiAutoSync = SettingKey<bool>(
    _SettingBoxKey.kazumiAutoSync,
    true,
    group: SettingGroup.sync,
  );
  static const minorMode = SettingKey<bool>(
    'minorMode',
    true,
    group: SettingGroup.misc,
  );

  // 🆕 公告版本号（用于“不再提示”功能）
  static const announcementVersion = SettingKey<int>(
    'announcementVersion',
    0,
    group: SettingGroup.notice,
  );

  // 🆕 追番更新提醒（新番推送通知）
  /// 总开关：是否开启追番更新提醒
  static const animeUpdateNotify = SettingKey<bool>(
    _SettingBoxKey.animeUpdateNotify,
    false,
    group: SettingGroup.notice,
  );
  /// 检查间隔（小时）：8/12/24
  static const animeUpdateCheckIntervalHours = SettingKey<int>(
    _SettingBoxKey.animeUpdateCheckIntervalHours,
    12,
    group: SettingGroup.notice,
  );
  /// 上次检查时间戳（ms），用于计算下次检查
  static const animeUpdateLastCheck = SettingKey<int>(
    _SettingBoxKey.animeUpdateLastCheck,
    0,
    group: SettingGroup.notice,
  );
  /// 仅提醒“在看”状态（true）或包含“想看”（false）
  static const animeUpdateOnlyWatching = SettingKey<bool>(
    _SettingBoxKey.animeUpdateOnlyWatching,
    true,
    group: SettingGroup.notice,
  );

  // 🆕 自定义收藏分组（本地功能，不参与同步）
  /// 分组数据：JSON 字符串，格式 {"分组名":[subjectId,...]}
  static const collectFolderMap = SettingKey<String>(
    _SettingBoxKey.collectFolderMap,
    '{}',
    group: SettingGroup.collect,
  );

  // 🆕 桌面端增强
  /// 记住窗口位置/大小，重启恢复
  static const windowRememberGeometry = SettingKey<bool>(
    _SettingBoxKey.windowRememberGeometry,
    true,
    group: SettingGroup.misc,
  );
  /// 系统托盘（桌面端）
  static const desktopTrayEnabled = SettingKey<bool>(
    _SettingBoxKey.desktopTrayEnabled,
    true,
    group: SettingGroup.misc,
  );
  /// 全局快捷键（桌面端，Ctrl+Alt+K 显示/隐藏窗口）
  static const globalHotkeyEnabled = SettingKey<bool>(
    _SettingBoxKey.globalHotkeyEnabled,
    false,
    group: SettingGroup.misc,
  );
  /// 记住的窗口几何信息：JSON {"x","y","w","h"}
  static const windowGeometry = SettingKey<String>(
    _SettingBoxKey.windowGeometry,
    '',
    group: SettingGroup.misc,
  );

  // 🆕 倍速记忆（按番剧）
  /// 是否记忆每部番的播放倍速
  static const playSpeedMemoryEnabled = SettingKey<bool>(
    _SettingBoxKey.playSpeedMemoryEnabled,
    true,
    group: SettingGroup.player,
  );
  /// 倍速记忆数据：JSON {"subjectId": 倍速}
  static const playSpeedMemory = SettingKey<String>(
    _SettingBoxKey.playSpeedMemory,
    '{}',
    group: SettingGroup.player,
  );

  // 🆕 下载完成通知
  static const downloadCompleteNotify = SettingKey<bool>(
    _SettingBoxKey.downloadCompleteNotify,
    true,
    group: SettingGroup.download,
  );

  // 🆕 续作/换季提醒
  static const sequelNotify = SettingKey<bool>(
    _SettingBoxKey.sequelNotify,
    true,
    group: SettingGroup.notice,
  );

  // 🆕 通知角标（桌面小圆点）
  static const notificationBadge = SettingKey<bool>(
    _SettingBoxKey.notificationBadge,
    true,
    group: SettingGroup.notice,
  );

  // 🆕 规则设置：选源排序偏好（默认按速度 / 清晰度 / 集数最多，可组合）
  static const ruleSortDefault = SettingKey<bool>(    _SettingBoxKey.ruleSortDefault,
    true,
    group: SettingGroup.misc,
  );
  static const ruleSortQuality = SettingKey<bool>(
    _SettingBoxKey.ruleSortQuality,
    false,
    group: SettingGroup.misc,
  );
  static const ruleSortEpisodes = SettingKey<bool>(
    _SettingBoxKey.ruleSortEpisodes,
    false,
    group: SettingGroup.misc,
  );
  static const ruleSortSpeed = SettingKey<bool>(
    _SettingBoxKey.ruleSortSpeed,
    false,
    group: SettingGroup.misc,
  );
  static const pendingThirdpartyLogin = SettingKey<bool>(
    _SettingBoxKey.pendingThirdpartyLogin,
    false,
    group: SettingGroup.misc,
  );

  // 🆕 社交：本地缓存的用户资料 JSON（uid/昵称/头像）
  static const socialProfile = SettingKey<String>(
    _SettingBoxKey.socialProfile,
    '',
    group: SettingGroup.misc,
  );

  // 🆕 省时统计：累计跳过的片头/片尾总秒数
  static const timeSavedSeconds = SettingKey<int>(
    _SettingBoxKey.timeSavedSeconds,
    0,
    group: SettingGroup.misc,
  );

  // 🆕 当前登录邮箱（判断是否 OAuth 一次性账号）
  static const kazumiEmail = SettingKey<String>(
    _SettingBoxKey.kazumiEmail,
    '',
    group: SettingGroup.misc,
  );

  // 🆕 全局好友消息横幅提醒（除播放页外，顶部弹出好友消息）
  static const chatGlobalBanner = SettingKey<bool>(
    _SettingBoxKey.chatGlobalBanner,
    true,
    group: SettingGroup.notice,
  );
  // 🆕 社交：聊天已读记录 JSON（{"好友uid": 最后已读消息id}）
  static const chatLastRead = SettingKey<String>(
    _SettingBoxKey.chatLastRead,
    '{}',
    group: SettingGroup.misc,
  );

  static final List<SettingKey<Object?>> all = [
    hAenable,
    autoSwitchSource,
    weeklyWatchGoal,
    skipOpDurations,
    skipEdDurations,
    skipOpDefaultSeconds,
    skipEdDefaultSeconds,
    hardwareDecoder,
    searchEnhanceEnable,
    autoUpdate,
    checkPluginUpdateOnStartup,
    alwaysOntop,
    defaultPlaySpeed,
    defaultShortcutForwardPlaySpeed,
    defaultAspectRatioType,
    buttonSkipTime,
    arrowKeySkipTime,
    danmakuEnhance,
    danmakuBorder,
    danmakuBorderSize,
    danmakuOpacity,
    danmakuFontSize,
    danmakuTop,
    danmakuScroll,
    danmakuBottom,
    danmakuMassive,
    danmakuDeduplication,
    danmakuArea,
    danmakuColor,
    danmakuDuration,
    danmakuLineHeight,
    danmakuTimeOffset,
    danmakuEnabledByDefault,
    danmakuBiliBiliSource,
    danmakuGamerSource,
    danmakuDanDanSource,
    customDanmakuEnabled,
    danmakuFontWeight,
    danmakuFollowSpeed,
    themeMode,
    themeColor,
    privateMode,
    autoPlay,
    autoPlayNext,
    preloadNextEpisode,
    nightEyeProtection,
    autoSelectSource,
    playResume,
    showPlayerError,
    oledEnhance,
    displayMode,
    enableGitProxy,
    enableBangumiProxy,
    enableSystemProxy,
    defaultStartupPage,
    isWideScreen,
    webDavEnable,
    webDavEnableHistory,
    webDavEnableCollect,
    webDavURL,
    webDavUsername,
    webDavPassword,
    lowMemoryMode,
    showWindowButton,
    useDynamicColor,
    exitBehavior,
    playerDebugMode,
    syncPlayEndPoint,
    androidEnableOpenSLES,
    androidVideoRenderer,
    androidAutoEnterPIP,
    defaultSuperResolutionMode,
    disableSuperResolutionWarning,
    playerDisableAnimations,
    playerLogLevel,
    timelineNotShowAbandonedBangumis,
    timelineNotShowWatchedBangumis,
    timelineOnlyShowWatchingBangumis,
    useSystemFont,
    forceAdBlocker,
    backgroundPlayback,
    proxyEnable,
    proxyConfigured,
    proxyUrl,
    proxyTestUrl,
    showRating,
    showAnimeCounter,
    downloadParallelEpisodes,
    downloadParallelSegments,
    downloadDanmaku,
    downloadDirectory,
    downloadDirectoryBookmark,
    shortcutDialogShown,
    bangumiSyncEnable,
    kazumiAutoSync,
    bangumiAccessToken,
    bangumiSyncPriority,
    bangumiImmediateSyncToastEnable,
    brightnessVolumeGesture,
    historySyncDeviceId,
    historySyncSequence,
    historySyncSnapshotInitialized,
    playerControllerLayerDisappearTime,
    defaultVolume,
    playerMuted,
    announcementVersion, // 新增
  ];

  static List<SettingKey<Object?>> byGroup(SettingGroup group) {
    return [
      for (final key in all)
        if (key.group == group) key
    ];
  }

  SettingsKeys._();
}

// Historical Hive key names used by settings created before the typed registry.
class _SettingBoxKey {
  static const String hAenable = 'hAenable',
      autoSwitchSource = 'autoSwitchSource',
      weeklyWatchGoal = 'weeklyWatchGoal',
      skipOpDurations = 'skipOpDurations',
      skipEdDurations = 'skipEdDurations',
      skipOpDefaultSeconds = 'skipOpDefaultSeconds',
      skipEdDefaultSeconds = 'skipEdDefaultSeconds',
      hardwareDecoder = 'hardwareDecoder',
      searchEnhanceEnable = 'searchEnhanceEnable',
      autoUpdate = 'autoUpdate',
      alwaysOntop = 'alwaysOntop',
      defaultPlaySpeed = 'defaultPlaySpeed',
      defaultShortcutForwardPlaySpeed = 'defaultShortcutForwardPlaySpeed',
      defaultAspectRatioType = 'defaultAspectRatioType',
      buttonSkipTime = 'buttonSkipTime',
      arrowKeySkipTime = 'arrowKeySkipTime',
      danmakuEnhance = 'danmakuEnhance',
      danmakuBorder = 'danmakuBorder',
      danmakuBorderSize = 'danmakuBorderSize',
      danmakuOpacity = 'danmakuOpacity',
      danmakuFontSize = 'danmakuFontSize',
      danmakuTop = 'danmakuTop',
      danmakuScroll = 'danmakuScroll',
      danmakuBottom = 'danmakuBottom',
      danmakuMassive = 'danmakuMassive',
      danmakuDeduplication = 'danmakuDeduplication',
      danmakuArea = 'danmakuArea',
      danmakuColor = 'danmakuColor',
      danmakuDuration = 'danmakuDuration',
      danmakuLineHeight = 'danmakuLineHeight',
      danmakuTimeOffset = 'danmakuTimeOffset',
      danmakuEnabledByDefault = 'danmakuEnabledByDefault',
      danmakuBiliBiliSource = 'danmakuBiliBiliSource',
      danmakuGamerSource = 'danmakuGamerSource',
      danmakuDanDanSource = 'danmakuDanDanSource',
      customDanmakuEnabled = 'customDanmakuEnabled',
      danmakuFontWeight = 'danmakuFontWeight',
      danmakuFollowSpeed = 'danmakuFollowSpeed',
      themeMode = 'themeMode',
      themeColor = 'themeColor',
      privateMode = 'privateMode',
      autoPlay = 'autoPlay',
      autoPlayNext = 'autoPlayNext',
      preloadNextEpisode = 'preloadNextEpisode',
      nightEyeProtection = 'nightEyeProtection',
      autoSelectSource = 'autoSelectSource',
      playResume = 'playResume',
      showPlayerError = 'showPlayerError',
      oledEnhance = 'oledEnhance',
      displayMode = 'displayMode',
      enableGitProxy = 'enableGitProxy',
      enableBangumiProxy = 'enableBangumiProxy',
      enableSystemProxy = 'enableSystemProxy',
      defaultStartupPage = 'defaultStartupPage',
      isWideScreen = 'isWideScreen',
      webDavEnable = 'webDavEnable',
      webDavEnableHistory = 'webDavEnableHistory',
      webDavEnableCollect = 'webDavEnableCollect',
      webDavURL = 'webDavURL',
      webDavUsername = 'webDavUsername',
      webDavPassword = 'webDavPasswd',
      lowMemoryMode = 'lowMemoryMode',
      showWindowButton = 'showWindowButton',
      useDynamicColor = 'useDynamicColor',
      exitBehavior = 'exitBehavior',
      playerDebugMode = 'playerDebugMode',
      syncPlayEndPoint = 'syncPlayEndPoint',
      androidEnableOpenSLES = 'androidEnableOpenSLES',
      androidVideoRenderer = 'androidVideoRenderer',
      androidAutoEnterPIP = 'androidAutoEnterPIP',
      defaultSuperResolutionMode = 'defaultSuperResolutionType',
      disableSuperResolutionWarning = 'superResolutionWarn',
      playerDisableAnimations = 'playerDisableAnimations',
      playerLogLevel = 'playerLogLevel',
      timelineNotShowAbandonedBangumis = 'timelineNotShowAbandonedBangumis',
      timelineNotShowWatchedBangumis = 'timelineNotShowWatchedBangumis',
      timelineOnlyShowWatchingBangumis = 'timelineOnlyShowWatchingBangumis',
      useSystemFont = 'useSystemFont',
      customFontPath = 'customFontPath',
      forceAdBlocker = 'forceAdBlocker',
      backgroundPlayback = 'backgroundPlayback',
      proxyEnable = 'proxyEnable',
      proxyConfigured = 'proxyConfigured',
      proxyUrl = 'proxyUrl',
      proxyTestUrl = 'proxyTestUrl',
      showRating = 'showRating',
      showAnimeCounter = 'showAnimeCounter',
      downloadParallelEpisodes = 'downloadParallelEpisodes',
      downloadParallelSegments = 'downloadParallelSegments',
      downloadDanmaku = 'downloadDanmaku',
      downloadDirectory = 'downloadDirectory',
      shortcutDialogShown = 'shortcutDialogShown',
      bangumiSyncEnable = 'bangumiSyncEnable',
      kazumiAutoSync = 'kazumiAutoSync',
      bangumiAccessToken = 'bangumiAccessToken',
      bangumiSyncPriority = 'bangumiSyncPriority',
      bangumiImmediateSyncToastEnable = 'bangumiImmediateSyncToastEnable',
      brightnessVolumeGesture = 'brightnessVolumeGesture',
      historySyncDeviceId = 'historySyncDeviceId',
      historySyncSequence = 'historySyncSequence',
      historySyncSnapshotInitialized = 'historySyncSnapshotInitialized',
      showLastWatchCard = 'showLastWatchCard',
      enableDesktopWidget = 'enableDesktopWidget',
      enableUpdateNotification = 'enableUpdateNotification',
      animeUpdateNotify = 'animeUpdateNotify',
      animeUpdateCheckIntervalHours = 'animeUpdateCheckIntervalHours',
      animeUpdateLastCheck = 'animeUpdateLastCheck',
      animeUpdateOnlyWatching = 'animeUpdateOnlyWatching',
      collectFolderMap = 'collectFolderMap',
      windowRememberGeometry = 'windowRememberGeometry',
      desktopTrayEnabled = 'desktopTrayEnabled',
      globalHotkeyEnabled = 'globalHotkeyEnabled',
      windowGeometry = 'windowGeometry',
      playSpeedMemoryEnabled = 'playSpeedMemoryEnabled',
      playSpeedMemory = 'playSpeedMemory',
      downloadCompleteNotify = 'downloadCompleteNotify',
      sequelNotify = 'sequelNotify',
      notificationBadge = 'notificationBadge',
      socialProfile = 'socialProfile',
      kazumiEmail = 'kazumiEmail',
      timeSavedSeconds = 'timeSavedSeconds',
      chatLastRead = 'chatLastRead',
      chatGlobalBanner = 'chatGlobalBanner',
      ruleSortDefault = 'ruleSortDefault',
      ruleSortQuality = 'ruleSortQuality',
      ruleSortEpisodes = 'ruleSortEpisodes',
      ruleSortSpeed = 'ruleSortSpeed',
      pendingThirdpartyLogin = 'pendingThirdpartyLogin';
}
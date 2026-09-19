import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/services/sync/bangumi_sync_service.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/plugin_editor/plugin_update_actions.dart';
import 'package:kazumi/services/download/background_download_service.dart';
import 'package:kazumi/services/platform/windows_shortcut.dart';
import 'package:kazumi/services/platform/platform_environment_service.dart';
import 'package:kazumi/services/update/startup_update_check.dart';
import 'package:kazumi/services/update/animeko_rule_updater.dart';
import 'package:kazumi/services/deep_link_service.dart';
import 'package:kazumi/services/font_service.dart';
import 'package:kazumi/services/notification/anime_update_notification_service.dart';
import 'package:kazumi/services/social/chat_banner_service.dart';
import 'package:kazumi/services/shortcut_service.dart';
import 'package:kazumi/services/social/chat_notification_poller.dart';
import 'package:kazumi/services/sync/kazumi_sync_service.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/navigation.dart';

class InitPage extends StatefulWidget {
  const InitPage({
    super.key,
    required this.pluginsController,
    required this.collectController,
    required this.shaderAssetService,
    required this.myController,
    required this.downloadController,
  });

  final PluginsController pluginsController;
  final CollectController collectController;
  final ShaderAssetService shaderAssetService;
  final MyController myController;
  final DownloadController downloadController;

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  PluginsController get pluginsController => widget.pluginsController;
  CollectController get collectController => widget.collectController;
  ShaderAssetService get shaderAssetService => widget.shaderAssetService;
  MyController get myController => widget.myController;
  DownloadController get downloadController => widget.downloadController;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeApp());
  }

  Future<void> _initializeApp() async {
    _migrateStorage();
    _loadShaders();
    _loadDanmakuShield();
    _webDavInit();
    _bangumiInit();
    try {
      await downloadController.init();
      _setupBackgroundDownloadNavigation();
    } catch (e) {
      KazumiLogger().e('InitPage: downloadController.init() failed', error: e);
    }

    await _checkRunningOnX11();
    await _showShortcutDialog();
    await _pluginInit();
    // ⭐ 加载自定义字体（如果之前选过字体文件）
    await FontService.loadIfNeeded();
    // 启动 Animeko 规则自动更新（后台静默检查，默认 60 分钟一次）
    final animekoUpdater = AnimekoRuleUpdater(pluginsController: pluginsController);
    unawaited(animekoUpdater.init());

    // 初始化深度链接服务（处理 yhdmgz:// 协议）
    final deepLinkService = DeepLinkService(pluginsController: pluginsController);
    unawaited(deepLinkService.init());

    // 初始化桌面快捷方式服务（点击番剧快捷方式 → 打开详情并自动弹选源）
    ShortcutService.init(onPlay: _handleShortcutPlay);

    // 启动樱花自动同步（登录后每 30 分钟同步收藏，默认开启）
    KazumiSyncService.startAutoSync();

    // 🆕 初始化追番更新提醒（收藏番剧有新集时推送通知，开关默认关闭）
    unawaited(AnimeUpdateNotificationService.init());

    // 🆕 启动全局好友消息横幅提醒（前台每 60 秒轮询，播放页不弹）
    ChatBannerService.start();

    // 🆕 好友聊天消息通知（前台每 30 秒轮询，登录时生效）
    ChatNotificationPoller.start();

    if (!mounted) {
      return;
    }
    // First launch: no installed rules yet, hand over to the onboarding flow.
    // 但如果用户曾经有过规则（有历史记录），直接进主页面
    if (pluginsController.pluginList.isEmpty &&
        GStorage.getSetting(SettingsKeys.animekoRuleLastCheck) <= 0 &&
        GStorage.getSetting(SettingsKeys.defaultStartupPage) == '/tab/popular/') {
      context.navigate('/onboarding');
      return;
    }

    if (!mounted) {
      return;
    }
    final updateController = myController;
    unawaited(runStartupUpdateCheck(
      isEnabled: () => GStorage.getSetting(SettingsKeys.autoUpdate),
      checkForUpdate: () async {
        await updateController.checkUpdate(type: 'auto');
      },
    ));
    _startDefaultPage();
  }

  /// 桌面快捷方式点击：打开番剧详情页并自动弹出选源（点一下源即播放）
  Future<void> _handleShortcutPlay(ShortcutPlayParams params) async {
    if (!mounted) return;
    try {
      final item = await BangumiApi.getBangumiInfoByID(params.id);
      if (item == null) {
        KazumiDialog.showToast(message: '未找到该番剧');
        return;
      }
      InfoPage.pendingEpisodeId = params.id;
      InfoPage.pendingEpisode = params.episode > 0 ? params.episode : null;
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (rootNavigatorKey.currentContext != null) {
          Navigator.of(rootNavigatorKey.currentContext!).pushNamed(
            '/info/',
            arguments: item,
          );
        }
      });
    } catch (e) {
      KazumiLogger().e('Shortcut: 打开番剧失败', error: e);
      KazumiDialog.showToast(message: '打开番剧失败');
    }
  }

  void _setupBackgroundDownloadNavigation() {
    final backgroundService = BackgroundDownloadService();

    backgroundService.onNavigateToDownloadRequested = () {
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final navigationContext = rootNavigatorKey.currentContext;
          if (navigationContext == null || !navigationContext.mounted) return;
          final path = navigationContext.routeState(listen: false).uri.path;
          if (path.contains('/download')) return;
          navigationContext.pushNamed('/settings/download/');
        } catch (e) {
          KazumiLogger()
              .w('InitPage: failed to navigate to download page', error: e);
        }
      });
    };

    backgroundService.onNotificationPermissionRequired = () async {
      final result = await KazumiDialog.show<bool>(
        clickMaskDismiss: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('需要通知权限'),
            content: const Text(
              '开启通知权限后，可以在后台下载时显示进度，并防止系统终止下载任务。\n\n'
              '如果拒绝，下载功能仍可使用，但在后台时可能被系统中断。',
            ),
            actions: [
              TextButton(
                onPressed: () => KazumiDialog.dismiss(popWith: false),
                child: Text(
                  '稍后再说',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              TextButton(
                onPressed: () => KazumiDialog.dismiss(popWith: true),
                child: const Text('允许'),
              ),
            ],
          );
        },
      );
      return result ?? false;
    };
  }

  void _startDefaultPage() {
    final defaultStartupPage =
        GStorage.getSetting(SettingsKeys.defaultStartupPage);
    if (!mounted) {
      return;
    }
    context.navigate(defaultStartupPage);
  }

  // migrate collect from old version (favorites)
  Future<void> _migrateStorage() async {
    await collectController.migrateCollect();
  }

  Future<void> _loadShaders() async {
    await shaderAssetService.copyShadersToExternalDirectory();
  }

  Future<void> _loadDanmakuShield() async {
    myController.loadShieldList();
  }

  Future<void> _webDavInit() async {
    bool webDavEnable = await GStorage.getSetting(SettingsKeys.webDavEnable);
    if (webDavEnable) {
      var webDav = WebDav();
      KazumiLogger().i('WebDav: Starting WebDav initialization');
      try {
        await webDav.init();
        try {
          await webDav.syncHistory();
          KazumiLogger().i('WebDav: Completed syncing watch history');
        } catch (e, stackTrace) {
          KazumiLogger().w(
            'WebDav: automatic watch history sync failed',
            error: e,
            stackTrace: stackTrace,
          );
        }
      } catch (e, stackTrace) {
        KazumiLogger().w(
          'WebDav: automatic initialization failed',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _bangumiInit() async {
    bool bangumiEnable =
        await GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    if (bangumiEnable) {
      var bangumi = BangumiSyncService();
      KazumiLogger().i('Bangumi: Starting Bangumi initialization');
      try {
        await bangumi.init();
      } catch (e) {
        bangumi.reset();
        await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
        KazumiLogger().w(
          'Bangumi: initialization failed, disabling Bangumi sync until user re-enables it',
          error: e,
        );
        KazumiDialog.showToast(
          message: '初始化Bangumi失败，已关闭 Bangumi 同步: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _checkRunningOnX11() async {
    if (!Platform.isLinux) {
      return;
    }
    bool isRunningOnX11 = await PlatformEnvironmentService.isRunningOnX11();
    if (isRunningOnX11) {
      await KazumiDialog.show(
        clickMaskDismiss: false,
        builder: (context) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('X11环境检测'),
              content: const Text(
                  '检测到您当前运行在X11环境下，Kazumi在X11环境下可能出现性能问题或界面异常，建议切换到Wayland以获得更好的体验。您是否希望在X11下继续使用Kazumi？'),
              actions: [
                TextButton(
                  onPressed: () {
                    exit(0);
                  },
                  child: Text(
                    '退出',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    KazumiDialog.dismiss();
                  },
                  child: const Text('继续'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _showShortcutDialog() async {
    if (!Platform.isWindows) return;
    if (GStorage.getSetting(SettingsKeys.shortcutDialogShown)) {
      return;
    }

    final create = await KazumiDialog.show<bool>(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: const Text('创建桌面快捷方式'),
        content: const Text('是否在桌面创建 Kazumi 的快捷方式？'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: Text('暂不创建',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    await GStorage.putSetting(SettingsKeys.shortcutDialogShown, true);
    if (create ?? false) {
      final success = await WindowsShortcut.createDesktopShortcut();
      KazumiDialog.showToast(message: success ? '桌面快捷方式已创建' : '桌面快捷方式创建失败');
    }
  }

  Future<void> _pluginInit() async {
    try {
      await pluginsController.init();
      unawaited(_pluginUpdate());
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'Plugin: failed to initialize rules',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _pluginUpdate() async {
    final checkOnStartup =
        GStorage.getSetting(SettingsKeys.checkPluginUpdateOnStartup);
    late final int count;
    try {
      count = await pluginsController.checkPluginUpdatesOnStartup(
        enabled: checkOnStartup,
      );
    } catch (_) {
      return;
    }
    if (count != 0) {
      KazumiDialog.showToast(
        message: '检测到 $count 条规则可以更新',
        showActionButton: true,
        actionLabel: '全部更新',
        onActionPressed: () => updateAllPluginsWithFeedback(
          pluginsController,
          ensureCatalog: false,
        ),
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LoadingWidget();
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container());
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/app_module.dart';
import 'package:kazumi/app_widget.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/pages/error/storage_error_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/services/platform/webview_feature_service.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';
// ✅ 新增导入：自动更新
import 'package:kazumi/services/update/auto_updater.dart';
// ✅ 新增导入：AppLinks深链
import 'package:app_links/app_links.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/logging/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
  }

  if (Platform.isAndroid) {
    await WebViewFeatureService.initialize();
  }

  try {
    final hivePath = '${(await getApplicationSupportDirectory()).path}/hive';
    await Hive.initFlutter(hivePath);
    await GStorage.init();
  } catch (e) {
    debugPrint('Storage initialization failed: $e');

    if (isDesktop()) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(null, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
    runApp(MaterialApp(
        title: '初始化失败',
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN")
        ],
        locale: const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN"),
        builder: (context, child) {
          return const StorageErrorPage();
        }));
    return;
  }
  bool showWindowButton =
      await GStorage.getSetting(SettingsKeys.showWindowButton);
  if (isDesktop()) {
    await windowManager.ensureInitialized();
    final lowResolution = await isLowResolution();
    WindowOptions windowOptions = WindowOptions(
      size: lowResolution ? const Size(840, 600) : const Size(1280, 860),
      center: true,
      skipTaskbar: false,
      titleBarStyle: (Platform.isMacOS || !showWindowButton)
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: showWindowButton,
      title: 'Kazumi',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  if (Platform.isWindows) {
    SystemProxyService.init();
  }
  ProxyManager.applyProxy();

  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
      },
      child: const AppWidget(),
    ),
  );

  // ✅ 初始化 AppLinks 深链监听（HTTPS域名无弹窗唤起）
  if (Platform.isAndroid || Platform.isIOS) {
    initAppLinks();
  }
}

// ========== AppLinks 深链监听（HTTPS域名无弹窗唤起） ==========
late AppLinks _appLinks;
bool _appLinksInitialized = false;

void initAppLinks() {
  if (_appLinksInitialized) return;
  _appLinksInitialized = true;

  _appLinks = AppLinks();

  // 1. 冷启动：通过链接直接打开APP
  _appLinks.getInitialAppLink().then((Uri? uri) {
    if (uri != null) {
      // 延迟1.2秒，等路由初始化完成再跳，避免"没路由"报错
      Future.delayed(const Duration(milliseconds: 1200), () {
        handleAppLink(uri);
      });
    }
  });

  // 2. APP后台挂着，通过链接再次唤起
  _appLinks.uriLinkStream.listen((Uri uri) {
    handleAppLink(uri);
  });
}

// 核心：解析HTTPS链接，跳动漫详情页
void handleAppLink(Uri uri) {
  final path = uri.path;
  final params = uri.queryParameters;

  int? animeId;

  // 格式1: https://qlyyz.xyz/anime/8573
  if (path.startsWith('/anime/')) {
    final idStr = path.replaceAll('/anime/', '').trim();
    animeId = int.tryParse(idStr);
  }
  // 格式2: https://qlyyz.xyz/share?id=8573（和你剪贴板分享逻辑一致）
  else if (path == '/share' && params['id'] != null) {
    animeId = int.tryParse(params['id']!);
  }
  // 格式3: https://qlyyz.xyz/toapp?route=anime&id=8573
  else if (params['route'] == 'anime' && params['id'] != null) {
    animeId = int.tryParse(params['id']!);
  }

  if (animeId != null) {
    _openAnimeDetail(animeId);
  }
}

// 通过ID拉取番剧信息 → 跳详情页（和DeepLinkService逻辑一致）
Future<void> _openAnimeDetail(int id) async {
  try {
    final item = await BangumiApi.getBangumiInfoByID(id);
    if (item == null) {
      _showToast('未找到该番剧');
      return;
    }
    if (rootNavigatorKey.currentContext == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Navigator.of(rootNavigatorKey.currentContext!).pushNamed(
          '/info/',
          arguments: item,
        );
      } catch (e) {
        KazumiLogger().e('AppLinks: 打开详情失败', error: e);
        _showToast('打开详情失败，请重试');
      }
    });
  } catch (e) {
    KazumiLogger().e('AppLinks: 打开番剧失败', error: e);
    _showToast('打开番剧失败');
  }
}

void _showToast(String message) {
  try {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      KazumiDialog.showToast(message: message);
    });
  } catch (_) {}
}

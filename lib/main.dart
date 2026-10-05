import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yhdm/app_module.dart';
import 'package:yhdm/app_widget.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/settings/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/storage/settings_keys.dart';
import 'package:yhdm/services/auth_service.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:yhdm/services/network/proxy_manager.dart';
import 'package:yhdm/services/network/system_proxy_service.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yhdm/pages/error/storage_error_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yhdm/utils/device.dart';
import 'package:yhdm/services/platform/webview_feature_service.dart';
import 'package:yhdm/services/platform/window_state_service.dart';
import 'package:yhdm/services/platform/global_hotkey_service.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/navigation.dart';
// ✅ 新增导入：自动更新
import 'package:yhdm/services/update/auto_updater.dart';
// ✅ 新增导入：AppLinks深链
import 'package:app_links/app_links.dart';
import 'package:yhdm/request/apis/bangumi_api.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/network/metered_network_service.dart';
// ✅ 新增导入：签名校验
import 'package:yhdm/services/signature/signature_service.dart';
import 'package:yhdm/services/stats_report_service.dart';
import 'package:yhdm/pages/signature/signature_error_page.dart';
import 'package:yhdm/services/network/ech_http_licenses.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yhdm/services/mcp/mcp_overlay.dart';
import 'package:yhdm/services/mcp/mcp_overlay_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ✅ ECH 图片加速依赖的第三方许可证注册（官方 2.3.6）
  registerEchHttpLicenses();
  // ✅ 签名校验：在一切业务初始化之前执行。
  // 未开启校验、或校验通过 → 进入正常主程序。
  // 校验失败 → 仅渲染独立错误页，主应用任何内容都不会加载。
  if (!await SignatureService.verify()) {
    runApp(const SignatureErrorPage());
    return;
  }
  MediaKit.ensureInitialized();
  // ✅ MCP 悬浮窗：注册点击切换监听（Android 防掉后台保活 + 快捷开关）
  McpOverlay.instance.init();
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
      // 🆕 恢复上次窗口位置/大小（需在 show 之前）
      await WindowStateService.restore();
      await windowManager.show();
      await windowManager.focus();
    });
  }
  if (Platform.isWindows) {
    SystemProxyService.init();
  }
  ProxyManager.applyProxy();

  // 🆕 启动上报统计（异步，失败静默）：设备码 + 手机型号 + IP
  unawaited(StatsReportService.reportStartup());

  // ⭐ 官方 2.3.2：网络感知低内存模式需要知道当前是不是移动数据
  await MeteredNetworkService.refresh();

  // 🆕 注册全局快捷键（Ctrl+Alt+K 显示/隐藏窗口，桌面端）
  if (isDesktop()) {
    unawaited(GlobalHotkeyService.apply());
  }

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
  _appLinks.getInitialLink().then((Uri? uri) {
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
  // 格式4: 网页版详情页分享
  // https://qlyyz.xyz/yhdm/detail.html?id=622206&n=尼古喵喵&c=ヤニねこ
  else if (path.endsWith('/yhdm/detail.html') && params['id'] != null) {
    final idStr = params['id']!.trim();
    animeId = int.tryParse(idStr);
    if (animeId == null) {
      KazumiLogger()
          .w('AppLinks: 网页版详情链接 id 非纯数字: $idStr');
    }
  }
  // 格式5: 网页版播放页分享（数据互通，跳 App 详情页兜底）
  else if (path.endsWith('/yhdm/player.html') && params['id'] != null) {
    animeId = int.tryParse(params['id']!.trim());
  }
  // 格式6: 网页版搜索链接 https://qlyyz.xyz/yhdm/search.html?wd=xxx
  else if (path.endsWith('/yhdm/search.html') && params['wd'] != null) {
    _openSearch(params['wd']!);
    return;
  }

  // 🆕 QQ 登录深链：yhdm://qq-auth?token=xxx
  else if (uri.scheme == 'yhdm' && uri.host == 'qq-auth') {
    final appToken = params['token'] ?? '';
    if (appToken.isNotEmpty) _handleThirdPartyToken(appToken, 'QQ');
    return;
  }

  // 🆕 微信登录深链：yhdm://wx-auth?token=xxx
  else if (uri.scheme == 'yhdm' && uri.host == 'wx-auth') {
    final appToken = params['token'] ?? '';
    if (appToken.isNotEmpty) _handleThirdPartyToken(appToken, '微信');
    return;
  }

  // 🆕 Telegram 登录深链：yhdm://tg-auth?token=xxx
  else if (uri.scheme == 'yhdm' && uri.host == 'tg-auth') {
    final appToken = params['token'] ?? '';
    if (appToken.isNotEmpty) _handleThirdPartyToken(appToken, 'Telegram');
    return;
  }

  // 🆕 抖音 登录深链：yhdm://dy-auth?token=xxx
  else if (uri.scheme == 'yhdm' && uri.host == 'dy-auth') {
    final appToken = params['token'] ?? '';
    if (appToken.isNotEmpty) _handleThirdPartyToken(appToken, '抖音');
    return;
  }

  // 🆕 yhdmgz:// 规则分享链接 — 转发给 DeepLinkService 处理
  if (uri.scheme == 'yhdmgz') {
    KazumiLogger().i('AppLinks: 转发 yhdmgz 链接给 DeepLinkService: $uri');
    // 通过 MethodChannel 转发，DeepLinkService 会处理规则导入
    const channel = MethodChannel('com.predidit.kazumi/intent');
    channel.invokeMethod('onIntent', {'url': uri.toString()});
    return;
  }

  if (animeId != null) {
    _openAnimeDetail(animeId,
        fallbackName: params['n']?.trim().isNotEmpty == true
            ? params['n']!.trim()
            : null);
  } else {
    KazumiLogger().w('AppLinks: 未识别的链接: ${uri.toString()}');
  }
}

/// 网页版搜索链接 → App 搜索页
void _openSearch(String keyword) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      Navigator.of(rootNavigatorKey.currentContext!).pushNamed(
        '/search/${Uri.encodeComponent(keyword)}',
      );
    } catch (e) {
      KazumiLogger().e('AppLinks: 打开搜索失败', error: e);
      _showToast('打开搜索失败');
    }
  });
}

/// 通过 ID 拉取番剧信息 → 跳详情页
/// [fallbackName] 网页版链接携带的番剧名（n 参数），
/// id 非 Bangumi subject_id 或查询失败时按名字搜索兜底。
Future<void> _openAnimeDetail(int id, {String? fallbackName}) async {
  try {
    var item = await BangumiApi.getBangumiInfoByID(id);
    // 兜底：ID 查不到时（例如 moonci 源的 vod_id），用名字在
    // Bangumi 搜索，取最优结果打开详情页，实现网页版与应用版互通。
    if (item == null && fallbackName != null) {
      KazumiLogger().i('AppLinks: ID $id 查询失败，按名字搜索: $fallbackName');
      final page = await BangumiApi.bangumiSearch(fallbackName, limit: 10);
      if (page != null && page.items.isNotEmpty) {
        final nameLower = fallbackName.toLowerCase();
        // 优先精确名匹配，否则取第一条
        item = page.items.firstWhere(
          (e) =>
              e.name.toLowerCase() == nameLower ||
              (e.nameCn.isNotEmpty && e.nameCn.toLowerCase() == nameLower),
          orElse: () => page.items.first,
        );
      }
    }
    if (item == null) {
      _showToast('未找到该番剧（ID: $id）');
      return;
    }
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) {
      _showToast('打开详情失败，请重试');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Navigator.of(ctx).pushNamed(
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
    _openServerSite('打开番剧失败');
  }
}

/// 🆕 第三方登录 token 深链回调处理
Future<void> _handleThirdPartyToken(String appToken, String providerName) async {
  // 🔧 已登录时不覆盖本地正式 token：绑定场景用户已有主账号正式 token，
  // 深链回调返回的是临时用户的临时 token，若覆盖会导致绑定成功后 token 失效（重启"登录已过期"）。
  // 绑定应由绑定页 _bindToken 完成，未登录场景才走这里正常登录保存 token。
  if (AuthService.getLocalToken() != null) return;
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    final request = await client.postUrl(
      Uri.parse('https://qlyyz.xyz/api/v1/login?action=verify_app_token'),
    );
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.add(utf8.encode(jsonEncode({
      'app_token': appToken,
      'device_name': AuthService.currentDeviceName(),
    })));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (data['token'] != null) {
      AuthService.saveLocalToken(data['token']);
      GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
      final user = data['user'];
      if (user is Map && user['email'] != null) {
        await AuthService.saveUserEmail(user['email'].toString());
      }
      // 🆕 将绑定状态写入 MySQL（深链登录不会自动写入 openid）
      try {
        final bindClient = HttpClient();
        bindClient.connectionTimeout = const Duration(seconds: 10);
        final bindReq = await bindClient.postUrl(
          Uri.parse('https://qlyyz.xyz/api/v1/sync?action=sync_bindinfo'));
        bindReq.headers.set('Content-Type', 'application/json; charset=utf-8');
        bindReq.headers.set('Authorization', 'Bearer ${data['token']}');
        bindReq.add(utf8.encode(jsonEncode({
          'provider': providerName == 'QQ' ? 'qq'
            : providerName == '微信' ? 'wechat'
            : providerName == 'Telegram' ? 'telegram'
            : providerName == '抖音' ? 'douyin' : '',
          'has_bind': user['has_qq'] == true || user['has_wechat'] == true
            || user['has_telegram'] == true || user['has_douyin'] == true,
        })));
        await bindReq.close();
        bindClient.close();
      } catch (_) {}
      // 🆕 保存 Bangumi token
      final bangumiToken = data['bangumi_token'];
      if (bangumiToken is String && bangumiToken.isNotEmpty) {
        await GStorage.putSetting(SettingsKeys.bangumiAccessToken, bangumiToken);
        await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
      }
      await GStorage.putSetting(SettingsKeys.pendingThirdpartyLogin, true);
      _showToast('$providerName 登录成功');
    } else {
      _showToast(data['error']?.toString() ?? '登录失败');
    }
  } catch (e) {
    _showToast('登录验证失败: $e');
  }
}

void _showToast(String message) {
  try {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      KazumiDialog.showToast(message: message);
    });
  } catch (_) {}
}

void _openServerSite(String message) {
  try {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      KazumiDialog.showToast(message: '$message，正在跳转...');
      launchUrl(
        Uri.parse('https://qlyyz.xyz/check.php'),
        mode: LaunchMode.externalApplication,
      );
    });
  } catch (_) {}
}

/// MCP 悬浮窗独立引擎入口（flutter_overlay_window 渲染悬浮窗 UI）。
/// 通过 @pragma('vm:entry-point') 注册为独立 entry point，随 App 一起打包。
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: McpOverlayView(),
  ));
}
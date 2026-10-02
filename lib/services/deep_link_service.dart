import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/webauth/webauth_page.dart';
import 'package:kazumi/pages/social/public_profile_page.dart';
import 'package:kazumi/plugins/animeko_converter.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/web_auth_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/encoding.dart';

/// yhdmgz:// 深度链接处理服务
///
/// 当用户在浏览器中点击 yhdmgz://base64 链接时：
/// 1. Android 系统通过 Intent 将链接传给 App
/// 2. 该服务解析链接中的 Base64 编码的规则 JSON
/// 3. 自动导入/更新规则
class DeepLinkService {
  static const _channel = MethodChannel('com.predidit.kazumi/intent');

  DeepLinkService({required this.pluginsController});

  final PluginsController pluginsController;

  StreamSubscription<dynamic>? _intentSubscription;

  /// 初始化：检查启动时是否有等待处理的链接
  Future<void> init() async {
    // ⭐ 等待路由初始化完成，避免冷启动时 pushNamed 找不到路由（"没路由"）
    await Future.delayed(const Duration(milliseconds: 1200));
    try {
      // 检查启动 Intent 中是否包含链接
      final intentData = await _channel.invokeMethod<String>('checkIntent');
      if (intentData != null && intentData.isNotEmpty) {
        await _handleLink(intentData);
      }
    } catch (e) {
      KazumiLogger().w('DeepLink: check intent failed', error: e);
    }

    // 检查剪贴板中是否有 yhdmgz:// 链接
    try {
      // 延迟一下确保剪贴板服务就绪
      await Future.delayed(const Duration(milliseconds: 800));
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        final text = clipboardData.text!.trim();
        if (text.startsWith('yhdmgz://') && !text.startsWith('yhdmgz://login')) {
          KazumiLogger().i('DeepLink: 从剪贴板检测到 yhdmgz 链接');
          await _handleLink(text);
          // 清空剪贴板，避免重复导入
          await Clipboard.setData(const ClipboardData(text: ''));
        } else if (text.contains('qlyyz.xyz/share')) {
          // 分享链接 https://qlyyz.xyz/share?id=123 → 转 yhdmgz://share/anime?id=123
          final uri = Uri.tryParse(text);
          final id = uri?.queryParameters['id'];
          if (id != null && id.isNotEmpty) {
            KazumiLogger().i('DeepLink: 从剪贴板检测到分享番剧链接');
            await _handleLink('yhdmgz://share/anime?id=$id');
            await Clipboard.setData(const ClipboardData(text: ''));
          }
        } else if (RegExp(r'\d{3,10}').hasMatch(text.trim())) {
          // 纯数字 ID（分享只复制 ID 时）：提取第一个连续数字串当作番剧 ID
          final match = RegExp(r'\d{3,10}').firstMatch(text.trim());
          final id = match?.group(0);
          if (id != null && id.isNotEmpty) {
            KazumiLogger().i('DeepLink: 从剪贴板检测到番剧ID: $id');
            await _handleLink('yhdmgz://share/anime?id=$id');
            await Clipboard.setData(const ClipboardData(text: ''));
          }
        }
      }
    } catch (e) {
      KazumiLogger().w('DeepLink: check clipboard failed', error: e);
    }

    // 监听应用运行时的新 Intent（onNewIntent）
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onIntent') {
        final url = call.arguments['url'] as String?;
        if (url != null && url.isNotEmpty) {
          await _handleLink(url);
        }
      }
    });
  }

  /// 处理深链（规则分享 yhdmgz:// 或登录回调 yhdm:// 或 https App Links）
  /// 🆕 网页版授权登录：整页确认授权 → 申请 code → 跳回浏览器（不再用弹窗）
  Future<void> _handleWebAuth(WebAuthRequest req) async {
    // 未登录 → 只提示，不跳浏览器（未点「同意授权」前一律不跳）
    if (AuthService.getLocalToken() == null) {
      _showToast('请先在 App 内登录樱花动漫账号，再重新打开授权链接');
      return;
    }

    final appName = req.appName.isNotEmpty ? req.appName : '该网页';

    // 整页确认授权（模仿 QQ 授权页：白底 + 权限列表），点「同意授权」后直接跳回浏览器
    // 冷启动深链时首页可能还没 build 完，直接跳浏览器会让用户
    // 「还没点同意就被跳走并报错」。这里最多等 ~3s 拿到可用 context。
    BuildContext? ctx = rootNavigatorKey.currentContext;
    for (int i = 0; i < 20; i++) {
      if (ctx != null && ctx.mounted) break;
      await Future.delayed(const Duration(milliseconds: 150));
      ctx = rootNavigatorKey.currentContext;
    }
    if (ctx == null || !ctx.mounted) {
      // 不再跳浏览器报错，留在 App 里提示，用户重开链接即可
      _showToast('授权页面还没准备好，请在 App 内重新打开该链接');
      return;
    }

    final decision = await WebAuthPage.push(ctx!, request: req);
    // ⭐ 只有用户点了「同意授权」才跳回浏览器；
    // 点「拒绝」或直接返回都留在 App，不再带着 error 把网页跳走
    if (decision != WebAuthDecision.approve) {
      _showToast(
          decision == WebAuthDecision.deny ? '你已拒绝该网页的授权' : '已取消授权');
      return;
    }

    // 申请一次性 code
    final res = await WebAuthService.requestCode(
      state: req.state,
      appName: appName,
    );
    if (res['success'] == true && res['code'] != null) {
      final back = WebAuthService.buildCallback(
        redirect: req.redirect,
        code: res['code'].toString(),
        state: req.state,
      );
      _showToast('授权成功，正在返回浏览器…');
      await _launchBrowser(back);
    } else {
      final back = WebAuthService.buildErrorCallback(
        redirect: req.redirect,
        error: res['error']?.toString() ?? 'unknown',
        state: req.state,
      );
      _showToast('授权失败：${res['error'] ?? '未知错误'}');
      await _launchBrowser(back);
    }
  }

  /// 用外部浏览器打开回跳地址
  Future<void> _launchBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      KazumiLogger().w('DeepLink: 打开浏览器失败', error: e);
    }
  }

  Future<void> _handleLink(String url) async {
    KazumiLogger().i('DeepLink: 收到链接: $url');

    // 0️⃣ App Links：https://qlyyz.xyz/open/xxx → 转成 yhdmgz:// 内部协议
    if (url.startsWith('https://qlyyz.xyz/')) {
      try {
        final uri = Uri.parse(url);
        // 分享番剧：/open/anime?id=123 → yhdmgz://share/anime?id=123
        if (uri.pathSegments.contains('open') && uri.pathSegments.contains('anime')) {
          final id = uri.queryParameters['id'];
          if (id != null && id.isNotEmpty) {
            url = 'yhdmgz://share/anime?id=$id';
          }
        }
        // 其他路径可以继续扩展...
      } catch (e) {
        KazumiLogger().w('DeepLink: App Links 解析失败', error: e);
      }
    }

    // 1️⃣ Bangumi OAuth 登录回调 (yhdm://bangumi-auth)
    if (url.startsWith('yhdm://bangumi-auth')) {
      try {
        final uri = Uri.parse(url);
        final token = uri.queryParameters['token'];
        if (token != null && token.isNotEmpty) {
          await GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
          await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
          KazumiLogger().i('DeepLink: Bangumi OAuth 登录成功');
          _showToast('Bangumi 登录成功 🎉');
        } else {
          _showToast('Bangumi 登录失败：未获取到 Token');
        }
      } catch (e) {
        KazumiLogger().e('DeepLink: Bangumi OAuth 回调处理失败', error: e);
        _showToast('Bangumi 登录失败：${e.toString()}');
      }
      return;
    }

    // 🆕 公开主页深链 yhdm://u/{uid} → 打开公开主页，可直接加好友/关注
    if (url.startsWith('yhdm://u/')) {
      try {
        final seg = url.replaceFirst('yhdm://u/', '').split('?')[0].split('/')[0];
        final uid = int.tryParse(seg);
        if (uid != null) {
          await _openPublicProfile(uid);
        } else {
          _showToast('链接无效');
        }
      } catch (e) {
        KazumiLogger().e('DeepLink: 打开主页失败', error: e);
        _showToast('打开主页失败');
      }
      return;
    }

    // 🆕 QQ OAuth 回调（登录或绑定）；GitHub 登录未实现，已移除对应死分支
    if (url.startsWith('yhdmgz://oauthqq')) {
      try {
        final uri = Uri.parse(url);
        final token = uri.queryParameters['token'];
        final bound = uri.queryParameters['bound'];
        final provider = uri.queryParameters['provider'] ?? 'QQ';
        final error = uri.queryParameters['error'];
        if (bound == '1') {
          _showToast('✅ 已绑定 $provider 账号');
          return;
        }
        if (token != null && token.isNotEmpty) {
          AuthService.saveLocalToken(token);
          await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
          KazumiLogger().i('DeepLink: OAuth 登录成功 provider=$provider');
          // 🆕 记录登录邮箱（判断是否 OAuth 一次性账号，用于"绑定邮箱"入口）
          try {
            final u = await AuthService.getUser(token);
            final uu = u['user'];
            if (uu is Map && uu['email'] != null) {
              await AuthService.saveUserEmail(uu['email'].toString());
            }
          } catch (_) {}
          _showToast('$provider 登录成功 🎉');
          // 初始化社交资料（建号分配 uid/昵称/头像）
          await SocialService.ensureProfileAfterLogin();
        } else {
          _showToast('$provider 登录失败：${error ?? '未知错误'}');
        }
      } catch (e) {
        KazumiLogger().e('DeepLink: OAuth 回调处理失败', error: e);
        _showToast('OAuth 登录失败：${e.toString()}');
      }
      return;
    }

    // 🆕 换包名迁移：yhdmgz://transfer?code=XXXXXXXX
    if (url.startsWith('yhdmgz://transfer')) {
      try {
        final code = Uri.parse(url).queryParameters['code']?.trim() ?? '';
        if (code.isEmpty) {
          _showToast('缺少迁移码');
          return;
        }
        final done = await AuthService.consumeTransferCode(code);
        if (done) _showToast('✅ 登录状态已迁移，无需重新登录');
      } catch (e) {
        _showToast('迁移失败: $e');
      }
      return;
    }

    // 🆕 网页版授权登录：yhdmgz://auth?redirect=xxx&state=yyy&app=zzz
    if (url.startsWith('yhdmgz://auth')) {
      final req = WebAuthService.parse(url);
      if (req == null) {
        _showToast('授权链接无效');
        return;
      }
      await _handleWebAuth(req);
      return;
    }

    // 2️⃣ 分享番剧深链：yhdmgz://share/anime?id=xxx（直接使用，无需落地页）
    if (url.startsWith('yhdmgz://share/anime')) {
      try {
        final uri = Uri.parse(url);
        final id = int.tryParse(uri.queryParameters['id'] ?? '');
        if (id != null) {
          await _openAnimeDetail(id);
        } else {
          _showToast('未找到该番剧');
        }
      } catch (e) {
        KazumiLogger().e('DeepLink: 分享番剧解析失败', error: e);
        _showToast('分享链接解析失败');
      }
      return;
    }

    // 3️⃣ 规则分享导入
    try {
      // 解析 Base64 → JSON
      final jsonStr = kazumiBase64ToJson(url);
      final data = jsonDecode(jsonStr);

      int count = 0;

      // 判断格式：单个 Plugin JSON 还是 Animeko 批量格式
      if (data is Map && data.containsKey('name') && data.containsKey('searchURL')) {
        // 单个 Kazumi Plugin 格式
        final plugin = Plugin.fromJson(Map<String, dynamic>.from(data));
        await pluginsController.updatePlugin(plugin);
        count = 1;
        KazumiLogger().i('DeepLink: 已导入规则: ${plugin.name}');
      } else if (data is Map || data is List) {
        // Animeko 批量格式
        final jsonStr2 = jsonEncode(data);
        final plugins = AnimekoRuleConverter.convertFromJson(jsonStr2);
        if (plugins.isEmpty) {
          KazumiLogger().w('DeepLink: 未找到可转换的规则');
          _showToast('未找到可转换的规则');
          return;
        }
        for (final plugin in plugins) {
          await pluginsController.updatePlugin(plugin);
          count++;
          KazumiLogger().i('DeepLink: 已导入规则: ${plugin.name}');
        }
      } else {
        KazumiLogger().w('DeepLink: 无法识别的规则格式');
        _showToast('无法识别的规则格式');
        return;
      }

      if (count > 0) {
        _showToast('成功导入 $count 条规则 🎉');
      }
    } catch (e, st) {
      KazumiLogger().e('DeepLink: 处理链接失败', error: e, stackTrace: st);
      _showToast('规则导入失败: ${e.toString()}');
    }
  }

  /// 打开公开主页（yhdm://u/{uid}）
  Future<void> _openPublicProfile(int uid) async {
    if (rootNavigatorKey.currentContext == null) {
      _showToast('无法打开主页');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final navContext = rootNavigatorKey.currentContext;
        if (navContext == null || !navContext.mounted) return;
        Navigator.of(navContext).push(
          MaterialPageRoute(builder: (_) => PublicProfilePage(uid: uid)),
        );
      } catch (e) {
        KazumiLogger().e('DeepLink: 打开公开主页失败', error: e);
        _showToast('打开主页失败');
      }
    });
  }

  /// 打开番剧详情页（拉取信息 → 等一帧 → push /info/）
  Future<void> _openAnimeDetail(int id) async {
    try {
      final item = await BangumiApi.getBangumiInfoByID(id);
      if (item == null) {
        _showToast('未找到该番剧');
        return;
      }
      if (rootNavigatorKey.currentContext == null) {
        _showToast('无法打开番剧详情');
        return;
      }
      // ⭐ 用 context.pushNamed 而不是 Navigator.pushNamed，
      //    因为项目用 flutter_modular 路由，Navigator 找不到模块化路由
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final navContext = rootNavigatorKey.currentContext;
          if (navContext == null || !navContext.mounted) return;
          navContext.pushNamed(
            '/info/',
            arguments: item,
          );
        } catch (e) {
          KazumiLogger().e('DeepLink: 打开详情失败', error: e);
          _showToast('打开详情失败，请重试');
        }
      });
    } catch (e) {
      KazumiLogger().e('DeepLink: 打开番剧失败', error: e);
      _showToast('打开番剧失败');
    }
  }

  /// 显示 Toast 提示（安全地在主线程执行）
  void _showToast(String message) {
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        KazumiDialog.showToast(message: message);
      });
    } catch (_) {
      // 静默失败
    }
  }

  /// 释放资源
  void dispose() {
    _intentSubscription?.cancel();
    _channel.setMethodCallHandler(null);
  }
}
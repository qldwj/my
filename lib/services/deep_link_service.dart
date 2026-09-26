import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';
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
  /// 🆕 网页版授权登录：弹确认框 → 申请 code → 跳回浏览器
  Future<void> _handleWebAuth(WebAuthRequest req) async {
    // 未登录 → 提示先登录
    if (AuthService.getLocalToken() == null) {
      _showToast('请先在 App 内登录樱花动漫账号');
      // 跳回浏览器并带错误
      final back = WebAuthService.buildErrorCallback(
        redirect: req.redirect,
        error: 'not_logged_in',
        state: req.state,
      );
      await _launchBrowser(back);
      return;
    }

    final appName = req.appName.isNotEmpty ? req.appName : '该网页';
    final host = Uri.tryParse(req.redirect)?.host ?? req.redirect;

    // 弹授权确认框
    final agreed = await KazumiDialog.show<bool>(
      builder: (context) => AlertDialog(
        title: const Text('授权登录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「$appName」请求使用你的樱花动漫账号登录。'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.language, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(host,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('将共享：账号身份（不含密码）',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('授权后该网页可代表你访问樱花动漫数据。',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意授权'),
          ),
        ],
      ),
    );

    if (agreed != true) {
      final back = WebAuthService.buildErrorCallback(
        redirect: req.redirect,
        error: 'denied',
        state: req.state,
      );
      await _launchBrowser(back);
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

    // 🆕 GitHub / QQ OAuth 回调（登录或绑定；两个专属协议）
    if (url.startsWith('yhdmgz://oauthgithub') ||
        url.startsWith('yhdmgz://oauthqq')) {
      try {
        final uri = Uri.parse(url);
        final token = uri.queryParameters['token'];
        final bound = uri.queryParameters['bound'];
        final provider = uri.queryParameters['provider'] ??
            (url.startsWith('yhdmgz://oauthgithub') ? 'GitHub' : 'QQ');
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
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart' show KazumiDialog;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bangumi OAuth 登录页面
/// 使用 Chrome Custom Tabs 授权（Android）/ ASWebAuthenticationSession（iOS）
/// 体验与 Telegram 一致：应用内打开授权页，共享系统浏览器 cookies，授权后自动跳回
class BangumiLoginPage extends StatefulWidget {
  const BangumiLoginPage({super.key});
  @override
  State<BangumiLoginPage> createState() => _BangumiLoginPageState();
}

class _BangumiLoginPageState extends State<BangumiLoginPage> {
  static const String _authBaseUrl = 'https://qlyyz.xyz/api/bangumi_oauth';
  static const String _redirectUri = 'yhdmgz://bangumi-auth';

  StreamSubscription<Uri>? _linkSub;
  final _appLinks = AppLinks();

  bool get _isLoggedIn => GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // 监听从 Custom Tabs 回调回来的 deep link
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      _handleCallback(uri);
    }, onError: (e) => KazumiLogger().e('AppLinks监听失败', error: e));
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  /// 处理回调：yhdmgz://bangumi-auth?token=xxx
  void _handleCallback(Uri uri) {
    if (uri.scheme == 'yhdmgz' && uri.host == 'bangumi-auth') {
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
        GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
        if (mounted) {
          setState(() {});
          KazumiDialog.showToast(message: '登录成功 🎉');
        }
      }
    }
  }

  Future<void> _login() async {
    try {
      final authUrl = '$_authBaseUrl?action=login&redirect_uri=$_redirectUri';
      final uri = Uri.parse(authUrl);

      if (await canLaunchUrl(uri)) {
        // inAppBrowserView = Chrome Custom Tabs（应用内，共享cookies，Telegram同款）
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    } catch (e) {
      KazumiLogger().e('Bangumi登录失败', error: e);
      KazumiDialog.showToast(message: '授权失败: $e');
    }
  }

  void _logout() async {
    final confirm = await KazumiDialog.show<bool>(
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定退出 Bangumi 登录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm == true) {
      await GStorage.putSetting(SettingsKeys.bangumiAccessToken, '');
      await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
      if (mounted) { KazumiDialog.showToast(message: '已退出'); Navigator.of(context).pop(false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: SysAppBar(title: const Text('Bangumi 登录')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bangumi Logo
                Icon(
                  _isLoggedIn ? Icons.check_circle_rounded : Icons.movie_filter_rounded,
                  size: 72,
                  color: _isLoggedIn ? Colors.green : theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                // 标题
                Text(
                  _isLoggedIn ? '已登录 Bangumi' : '授权登录 Bangumi',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLoggedIn ? '收藏、观看历史已同步' : '登录后可同步收藏与观看历史',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                // 授权按钮
                if (!_isLoggedIn)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _login,
                      icon: const Icon(Icons.open_in_browser_rounded),
                      label: const Text('授权登录', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                // 退出按钮
                if (_isLoggedIn)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _logout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text('退出登录'),
                    ),
                  ),
                const SizedBox(height: 24),
                // 提示
                Text(
                  '将跳转至浏览器完成授权，无需手动粘贴 Token',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

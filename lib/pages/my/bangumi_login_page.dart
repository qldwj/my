import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart' show KazumiDialog;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bangumi OAuth 登录页面
/// 使用应用内浏览器（Chrome Custom Tabs）授权登录
class BangumiLoginPage extends StatefulWidget {
  const BangumiLoginPage({super.key});
  @override
  State<BangumiLoginPage> createState() => _BangumiLoginPageState();
}

class _BangumiLoginPageState extends State<BangumiLoginPage> {
  // 授权地址
  static const String _authBaseUrl = 'https://qlyyz.xyz/api/bangumi_oauth';
  // 回调地址格式：yhdmgz://bangumi-auth?token=xxx
  static const String _redirectUri = 'yhdmgz://bangumi-auth';

  StreamSubscription<Uri>? _linkSubscription;
  final _appLinks = AppLinks();

  bool get _isLoggedIn => GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // 监听从浏览器回调回来的deep link
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri uri) {
      _handleCallback(uri);
    }, onError: (err) {
      KazumiLogger().e('AppLinks监听失败', error: err);
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  /// 处理回调URL：yhdmgz://bangumi-auth?token=xxx
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

      // 使用应用内浏览器打开（Android: Chrome Custom Tabs）
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.inAppBrowserView, // 应用内浏览器
          browserConfiguration: const LaunchBrowserConfiguration(
            showTitle: true,
          ),
        );
      } else {
        // 降级到外部浏览器
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      KazumiLogger().e('Bangumi登录失败', error: e);
      KazumiDialog.showToast(message: '打开授权页面失败: $e');
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

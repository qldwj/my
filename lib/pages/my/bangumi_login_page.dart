import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart' show KazumiDialog;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Bangumi OAuth 登录页面
/// 使用 flutter_web_auth_2 实现应用内授权
/// - Android: Chrome Custom Tabs（应用内显示，共享系统浏览器cookies）
/// - iOS: ASWebAuthenticationSession（应用内弹窗，共享Safari cookies）
/// - Web: Popup 窗口模式
class BangumiLoginPage extends StatefulWidget {
  const BangumiLoginPage({super.key});
  @override
  State<BangumiLoginPage> createState() => _BangumiLoginPageState();
}

class _BangumiLoginPageState extends State<BangumiLoginPage> {
  /// Bangumi OAuth 授权端点
  static const String _authBaseUrl = 'https://qlyyz.xyz/api/bangumi_oauth';

  /// 自定义 URL Scheme 回调地址
  /// 格式: yhdmgz://bangumi-auth?token=xxx
  static const String _callbackScheme = 'yhdmgz';
  static const String _redirectUri = 'yhdmgz://bangumi-auth';

  bool get _isLoggedIn =>
      GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;

  Future<void> _login() async {
    try {
      // 1. 构建授权 URL
      final authUrl = Uri.parse('$_authBaseUrl?action=login').replace(
        queryParameters: {
          'redirect_uri': _redirectUri,
        },
      );

      // 2. 调用 flutter_web_auth_2 拉起认证窗口
      //    - Android: Chrome Custom Tabs（应用内，共享Chrome cookies）
      //    - iOS: ASWebAuthenticationSession（应用内，共享Safari cookies）
      //    - Web: Popup窗口（需配合服务器端回调）
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: _callbackScheme,
        options: FlutterWebAuth2Options(
          preferEphemeral: false, // 共享系统浏览器cookies
        ),
      );

      // 3. 解析回调 URL
      //    回调格式: yhdmgz://bangumi-auth?token=xxx
      final callbackUri = Uri.parse(result);
      final token = callbackUri.queryParameters['token'];

      if (token == null || token.isEmpty) {
        KazumiDialog.showToast(message: '授权失败：未获取到 Token');
        return;
      }

      // 4. 保存 token
      await GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
      await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);

      if (mounted) {
        setState(() {});
        KazumiDialog.showToast(message: '登录成功 🎉');
      }
    } on Exception catch (e) {
      KazumiLogger().e('Bangumi登录失败', error: e);
      // 用户取消授权时不弹错误提示
      if (!e.toString().contains('cancelled')) {
        KazumiDialog.showToast(message: '授权失败: $e');
      }
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

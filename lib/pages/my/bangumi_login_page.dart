import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart' show KazumiDialog;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Bangumi OAuth 登录页面
/// 使用应用内浏览器授权（Chrome Custom Tabs）
class BangumiLoginPage extends StatefulWidget {
  const BangumiLoginPage({super.key});
  @override
  State<BangumiLoginPage> createState() => _BangumiLoginPageState();
}

class _BangumiLoginPageState extends State<BangumiLoginPage> {
  // 回调 URL Scheme，与 AndroidManifest.xml 中配置的一致
  static const String _callbackUrlScheme = 'yhdmgz';
  // 授权地址
  static const String _authBaseUrl = 'https://qlyyz.xyz/api/bangumi_oauth';
  // 回调地址格式：yhdmgz://bangumi-auth?token=xxx
  static const String _redirectUri = 'yhdmgz://bangumi-auth';

  bool get _isLoggedIn => GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;

  Future<void> _login() async {
    try {
      // 构建授权URL，包含redirect_uri参数
      final authUrl = '$_authBaseUrl?action=login&redirect_uri=$_redirectUri';
      
      // 使用应用内浏览器打开授权页面（Chrome Custom Tabs）
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: _callbackUrlScheme,
        options: FlutterWebAuth2Options(
          useWebview: true, // 在应用内打开浏览器
          windowName: '_self',
        ),
      );
      
      // 解析返回的URL获取token
      // 回调格式：yhdmgz://bangumi-auth?token=xxx
      final uri = Uri.parse(result);
      final token = uri.queryParameters['token'];
      
      if (token != null && token.isNotEmpty) {
        // 保存token
        await GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
        await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
        
        if (mounted) {
          setState(() {});
          KazumiDialog.showToast(message: '登录成功 🎉');
        }
      } else {
        KazumiDialog.showToast(message: '授权失败：未获取到Token');
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

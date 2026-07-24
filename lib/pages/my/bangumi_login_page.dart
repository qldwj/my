import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bangumi OAuth 登录页面
///
/// 和 Animeko 一样的登录方式：
/// 1. 点击「Bangumi 登录」→ 浏览器打开 OAuth 授权页
/// 2. 用户授权后自动跳转，拿到 token
class BangumiLoginPage extends StatefulWidget {
  const BangumiLoginPage({super.key});

  @override
  State<BangumiLoginPage> createState() => _BangumiLoginPageState();
}

class _BangumiLoginPageState extends State<BangumiLoginPage> {
  final TextEditingController _tokenController = TextEditingController();

  /// 你自己的 OAuth 后端地址（单文件版）
  static const String _loginUrl = 'https://qlyyz.xyz/bangumi_oauth.php?action=login';

  bool get _isLoggedIn =>
      GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;

  /// 打开你自己的 OAuth 后端 → 自动跳转 Bangumi 授权 → 回调拿 token → 跳回 App
  Future<void> _login() async {
    final uri = Uri.tryParse(_loginUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) KazumiDialog.showToast(message: '无法打开浏览器: $e');
      }
    }
  }

  /// 保存 Token
  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      KazumiDialog.showToast(message: '请输入 Access Token');
      return;
    }
    await GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
    await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
    if (mounted) {
      KazumiDialog.showToast(message: 'Bangumi 登录成功 🎉');
      Navigator.of(context).pop(true);
    }
  }

  /// 退出登录
  Future<void> _logout() async {
    final confirm = await KazumiDialog.show<bool>(
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出 Bangumi 登录吗？'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: Text('取消',
                style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
          ),
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('确定退出'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await GStorage.putSetting(SettingsKeys.bangumiAccessToken, '');
      await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
      _tokenController.clear();
      if (mounted) {
        setState(() {});
        KazumiDialog.showToast(message: '已退出 Bangumi');
      }
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Bangumi 登录')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),

          // Logo
          Icon(Icons.person, size: 72, color: colorScheme.primary),
          const SizedBox(height: 16),
          Text('Bangumi',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _isLoggedIn ? '已登录 ✅' : '登录后同步收藏与进度',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 40),

          if (!_isLoggedIn) ...[
            // Bangumi 登录按钮
            FilledButton.icon(
              onPressed: _login,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Bangumi 登录'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '通过浏览器完成 Bangumi 授权',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),

            // 手动输入 Token
            Text('或者手动输入 Access Token',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              decoration: InputDecoration(
                hintText: '粘贴 access_token',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saveToken,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('保存'),
            ),
          ],

          if (_isLoggedIn) ...[
            // 已登录状态
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, size: 48, color: Colors.green),
                  const SizedBox(height: 12),
                  const Text('已登录',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('退出登录'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

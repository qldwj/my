import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bangumi OAuth 登录页面（新版 UI）
class BangumiLoginPage extends StatefulWidget {
  const BangumiLoginPage({super.key});
  @override
  State<BangumiLoginPage> createState() => _BangumiLoginPageState();
}

class _BangumiLoginPageState extends State<BangumiLoginPage> {
  static const String _authBaseUrl = 'https://qlyyz.xyz/api/bangumi_oauth';
  static const String _redirectUri = 'yhdm://bangumi-auth';

  StreamSubscription<Uri>? _linkSub;
  final _appLinks = AppLinks();
  int? _expandedFaq;

  bool get _isLoggedIn => GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _linkSub = _appLinks.uriLinkStream.listen((uri) async {
      if (uri.scheme == 'yhdm' && uri.host == 'bangumi-auth') {
        final token = uri.queryParameters['token'];
        if (token != null && token.isNotEmpty) {
          GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
          GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
          // 🆕 通知后端：樱花账号绑定 Bangumi（这样 KazumiLoginPage 的 _loadStatus()
          // 才能正确返回 has_bangumi=true，显示"已绑定"）
          final myToken = AuthService.getLocalToken();
          if (myToken != null) {
            await AuthService.bindBangumi(token);
          }
          if (mounted) {
            setState(() {});
            KazumiDialog.showToast(message: '登录成功 🎉');
            // 返回上一页并刷新
            Navigator.of(context).pop(true);
          }
        }
      }
    }, onError: (e) => KazumiLogger().e('AppLinks监听失败', error: e));
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _login() async {
    try {
      final authUrl = '$_authBaseUrl?action=login&redirect_uri=$_redirectUri';
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
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
      GStorage.putSetting(SettingsKeys.bangumiAccessToken, '');
      GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
      if (mounted) {
        setState(() {});
        KazumiDialog.showToast(message: '已退出 Bangumi 登录');
      }
    }
  }

  void _toggleFaq(int index) {
    setState(() {
      _expandedFaq = _expandedFaq == index ? null : index;
    });
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
          // 图标
          Image.asset('assets/images/icons/bangumi.png', width: 72, height: 72),
          const SizedBox(height: 16),
          const Text('授权 Bangumi 登录',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('授权 Bangumi 账号，可以同步你的观看记录到 Bangumi',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 32),

          if (!_isLoggedIn) ...[
            FilledButton(
              onPressed: _login,
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: const Text('登录 / 注册', style: TextStyle(fontSize: 17)),
            ),
            const SizedBox(height: 12),
            // 🆕 检查 Bangumi 服务状态
            InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://bgm-status.ry.mk'),
                mode: LaunchMode.externalApplication,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('检查 Bangumi 状态',
                    style: TextStyle(fontSize: 13, color: colorScheme.outline)),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 16, color: colorScheme.outline),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                const Icon(Icons.check_circle, size: 48, color: Colors.green),
                const SizedBox(height: 12),
                const Text('已登录', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
                    child: const Text('退出登录'),
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 32),
          // 帮助标题
          Text('帮助', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          const SizedBox(height: 12),

          // FAQ 列表
          _buildFaq(0, 'Bangumi 是什么？',
            'Bangumi（bgm.tv）是一个动漫、游戏、音乐的收藏和追番管理平台。绑定后可以自动同步你的追番列表和观看进度。'),
          _buildFaq(1, '浏览器提示网站被屏蔽或禁止访问',
            '请尝试以下方法：\n1. 切换网络（WiFi/移动数据）\n2. 使用科学上网工具\n3. 清除浏览器缓存后重试'),
          _buildFaq(2, '注册时应该选择哪一项？',
            '注册 Bangumi 账号时，选择"个人用户"即可。填写昵称和密码后完成注册。'),
          _buildFaq(3, '注册登录时一直提示验证码错误',
            '请确认输入的验证码完全正确（区分大小写）。如果多次失败，请等待 60 秒后重新获取验证码。'),
          _buildFaq(4, '无法收到验证码',
            '检查邮箱垃圾邮件文件夹。如果仍未收到，请确认注册时填写的邮箱地址正确，或尝试更换邮箱。'),
          _buildFaq(5, '注册时一直提示激活失败',
            '请检查注册邮箱是否已激活（点击邮件中的激活链接）。如果链接已过期，重新注册即可。'),

          const SizedBox(height: 16),
          // 其他问题
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('无法解决你的问题？',
                  style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text('还可以通过以下方法解决', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                const SizedBox(height: 12),
                _buildLink('GitHub', 'https://github.com/qldwj/Kazumikfc', Icons.code),
                _buildLink('官网', 'https://qlyyz.xyz', Icons.language),
                _buildLink('Telegram', 'https://t.me/yhdmdchapp', Icons.send),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFaq(int index, String title, String content) {
    final colorScheme = Theme.of(context).colorScheme;
    final isExpanded = _expandedFaq == index;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _toggleFaq(index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500))),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: colorScheme.outline),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(height: 8),
                Text(content, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLink(String label, String url, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

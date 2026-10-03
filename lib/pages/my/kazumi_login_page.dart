import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/account_status_cache.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/sync/kazumi_sync_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/pages/my/qrcode_login_page.dart';
import 'package:kazumi/pages/my/device_sessions_page.dart';
import 'package:kazumi/pages/my/profile_edit_page.dart';
import 'package:kazumi/pages/my/qq_login_page.dart';
import 'package:kazumi/pages/my/wechat_login_page.dart';
import 'package:kazumi/pages/my/telegram_login_page.dart';
import 'package:kazumi/pages/my/douyin_login_page.dart';
import 'package:kazumi/pages/my/bangumi_login_page.dart';

class KazumiLoginPage extends StatefulWidget {
  const KazumiLoginPage({super.key});
  @override
  State<KazumiLoginPage> createState() => _KazumiLoginPageState();
}

class _KazumiLoginPageState extends State<KazumiLoginPage> {
  bool _loggedIn = false;
  bool _syncing = false;
  bool _sendingCode = false;
  bool _logging = false;
  String? _captchaChallenge;
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _captchaController = TextEditingController();
  Map<String, bool> _status = {
    'has_qq': false, 'has_wechat': false, 'has_telegram': false,
    'has_douyin': false, 'has_bangumi': false, 'has_email': false,
  };

  @override
  void initState() {
    super.initState();
    _checkPendingLogin();
  }

  /// 打开官网网页版登录（真实可用）
  Future<void> _launchWebLogin() async {
    final url = Uri.parse('https://qlyyz.xyz');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      KazumiDialog.showToast(message: '无法打开浏览器');
    }
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) { KazumiDialog.showToast(message: '请输入邮箱'); return; }
    setState(() { _sendingCode = true; _captchaChallenge = null; });
    try {
      final res = await AuthService.sendCode(email);
      if (res['captcha_challenge'] != null) {
        setState(() => _captchaChallenge = res['captcha_challenge']);
        KazumiDialog.showToast(message: '验证码已发送');
      } else {
        KazumiDialog.showToast(message: res['error'] ?? '发送失败');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '网络错误');
    }
    setState(() => _sendingCode = false);
  }

  Future<void> _loginWithEmail() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final captcha = _captchaController.text.trim();
    if (code.length != 6) { KazumiDialog.showToast(message: '请输入6位验证码'); return; }
    setState(() => _logging = true);
    try {
      final res = await AuthService.login(email: email, code: code, captchaAnswer: captcha,
        deviceName: AuthService.currentDeviceName());
      if (res['token'] != null) {
        AuthService.saveLocalToken(res['token']);
        GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
        await SocialService.ensureProfileAfterLogin();
        // 🆕 登录后把当前账号保存进「切换账号」列表（持久化）
        await AuthService.upsertCurrentAccount(
          nickname: SocialService.myProfile?.nickname,
          avatar: SocialService.myProfile?.avatar,
          uid: SocialService.myProfile?.uid,
        );
        if (res['user'] is Map && res['user']['email'] != null) {
          await AuthService.saveUserEmail(res['user']['email'].toString());
        }
        if (mounted) {
          setState(() { _logging = false; });
          KazumiDialog.showToast(message: '登录成功');
          _refreshLoginState();
        }
      } else {
        if (mounted) { setState(() { _logging = false; }); KazumiDialog.showToast(message: res['error'] ?? '登录失败'); }
      }
    } catch (e) {
      if (mounted) { setState(() { _logging = false; }); KazumiDialog.showToast(message: '网络错误'); }
    }
  }

  /// 检测 main.dart 深链登录标记，自动刷新
  void _checkPendingLogin() async {
    final pending = GStorage.getSetting(SettingsKeys.pendingThirdpartyLogin);
    if (pending == true) {
      await GStorage.putSetting(SettingsKeys.pendingThirdpartyLogin, false);
      _refreshLoginState();
    } else {
      _refreshLoginState();
    }
  }

  /// 刷新登录状态
  void _refreshLoginState() {
    _loggedIn = AuthService.isLoggedIn;
    if (_loggedIn) {
      // 🆕 先用本地 Hive 缓存渲染（含 6 项绑定状态）
      final cached = AccountStatusCache.readStatus();
      if (cached != null) {
        _status = {
          'has_qq': cached['has_qq'] == true,
          'has_wechat': cached['has_wechat'] == true,
          'has_telegram': cached['has_telegram'] == true,
          'has_douyin': cached['has_douyin'] == true,
          'has_bangumi': cached['has_bangumi'] == true,
          'has_email': cached['has_email'] == true,
        };
      }
      _loadStatus(); // 只要已登录就加载状态
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadStatus() async {
    // 🆕 5 分钟内已有本地缓存就不再打服务器
    if (!AccountStatusCache.shouldRefresh && AccountStatusCache.readStatus() != null) {
      return;
    }
    try {
      final token = AuthService.getLocalToken();
      if (token == null) return;
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(Uri.parse('https://qlyyz.xyz/api/v1/login?action=login_status'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $token');
      request.add(utf8.encode('{}'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['success'] == true && mounted) {
        final statusData = data['data'] as Map<String, dynamic>? ?? {};
        setState(() {
          _status = {
            'has_qq': statusData['has_qq'] ?? false,
            'has_wechat': statusData['has_wechat'] ?? false,
            'has_telegram': statusData['has_telegram'] ?? false,
            'has_douyin': statusData['has_douyin'] ?? false,
            'has_bangumi': statusData['has_bangumi'] ?? false,
            'has_email': statusData['has_email'] ?? false,
          };
        });
        // 🆕 落到 Hive
        AccountStatusCache.saveStatus(statusData);
      }
    } catch (e) {}
  }

  /// 🆕 换包名迁移：生成一次性迁移码给新 App 用
  Future<void> _showTransferDialog() async {
    KazumiDialog.showLoading(msg: '生成中');
    final res = await AuthService.createTransferCode();
    KazumiDialog.dismiss();
    if (!mounted) return;
    if (res['success'] != true) {
      KazumiDialog.showToast(message: '${res['error'] ?? '生成失败'}');
      return;
    }
    final code = (res['code'] ?? '').toString();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('迁移码已生成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              code,
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 3),
            ),
            const SizedBox(height: 10),
            Text(
              '约 90 秒内有效、只能用一次。\n'
              '在新版 App 的「账号」页点「我有迁移码」输入这串码，'
              '即可直接继承当前登录，不用重新登录。',
              style: TextStyle(
                  fontSize: 13, color: Theme.of(ctx).colorScheme.outline),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (ctx.mounted) Navigator.pop(ctx);
              KazumiDialog.showToast(message: '迁移码已复制');
            },
            child: const Text('复制并关闭'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 🆕 换包名迁移：输入迁移码，直接继承旧 App 的登录态
  Future<void> _importTransferCode() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('我有迁移码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 8,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  hintText: '例如 7KQF2M8X', counterText: ''),
            ),
            const SizedBox(height: 4),
            Text('迁移码在旧版 App「账号」页生成，90 秒内有效、只能用一次。',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(ctx).colorScheme.outline)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('立即迁移')),
        ],
      ),
    );
    final code = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || code.isEmpty || !mounted) return;
    final done = await AuthService.consumeTransferCode(code);
    if (!mounted) return;
    if (done) {
      KazumiDialog.showToast(message: '✅ 登录状态已迁移，无需重新登录');
      try {
        await SocialService.ensureProfileAfterLogin();
      } catch (_) {}
      _refreshLoginState();
      setState(() {});
    }
  }

  void _logout() {
    AccountStatusCache.clear();   // 🆕 退出登录必须清掉账号状态缓存
    AuthService.clearLocalToken();
    SocialService.clearProfileCache();
    GStorage.putSetting(SettingsKeys.kazumiSyncEnable, false);
    setState(() {
      _loggedIn = false;
      _status = {'has_qq': false, 'has_wechat': false, 'has_telegram': false, 'has_douyin': false, 'has_bangumi': false, 'has_email': false};
    });
    KazumiDialog.showToast(message: '已退出登录');
  }

  /// 🆕 销毁账号：直接删除，不可恢复
  Future<void> _deleteAccount() async {
    final confirm = await KazumiDialog.show<bool>(
      builder: (ctx) => AlertDialog(
        title: const Text('销毁账号', style: TextStyle(color: Colors.red)),
        content: const Text(
          '销毁后将删除该账号和全部云端数据（收藏/历史/进度/好友），不可恢复。确定销毁？',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认销毁'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    KazumiDialog.showLoading(msg: '删除中');
    final error = await SocialService.requestDeleteAccount();
    KazumiDialog.dismiss();
    AuthService.clearLocalToken();
    AccountStatusCache.clear();
    SocialService.clearProfileCache();
    GStorage.putSetting(SettingsKeys.kazumiSyncEnable, false);
    if (!mounted) return;
    setState(() {
      _loggedIn = false;
      _status = {
        'has_qq': false, 'has_wechat': false, 'has_telegram': false,
        'has_douyin': false, 'has_bangumi': false, 'has_email': false,
      };
    });
    KazumiDialog.showToast(message: error != null ? '❌ $error' : '✅ 账号已删除');
  }

  Future<void> _syncCollect() async {
    setState(() => _syncing = true);
    try {
      final msg = await KazumiSyncService.syncCollect();
      KazumiDialog.showToast(message: msg);
    } catch (e) {
      KazumiDialog.showToast(message: '同步失败: $e');
    }
    setState(() => _syncing = false);
  }

  Future<void> _onAuthResult(bool? result) async {
    if (result == true) {
      _refreshLoginState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('樱花动漫账号'),
        actions: [
          if (_loggedIn) IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileEditPage())),
            icon: const Icon(Icons.edit_rounded), tooltip: '编辑资料',
          ),
          if (_loggedIn) IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QrcodeLoginPage())),
            icon: const Icon(Icons.qr_code), tooltip: '生成登录二维码',
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 16),
        // 状态卡片
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _loggedIn ? Colors.green.shade50 : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            Icon(_loggedIn ? Icons.check_circle : Icons.person, size: 48,
              color: _loggedIn ? Colors.green : cs.outline),
            const SizedBox(height: 8),
            Text(_loggedIn ? '已登录' : '未登录', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 16),

        if (!_loggedIn) ...[
          // ========== 未登录：邮箱登录直接显示，第三方登录在下方 ==========
          Text('邮箱登录', style: TextStyle(fontSize: 14, color: cs.outline)),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _codeController, maxLength: 6,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '验证码', border: OutlineInputBorder()))),
            const SizedBox(width: 12),
            FilledButton.tonal(onPressed: _sendingCode ? null : _sendCode,
              child: _sendingCode
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('发送验证码')),
          ]),
          if (_captchaChallenge != null) ...[
            const SizedBox(height: 12),
            TextField(controller: _captchaController, maxLength: 6,
              decoration: InputDecoration(labelText: '人机验证', border: const OutlineInputBorder(),
                suffixIcon: Padding(padding: const EdgeInsets.all(12),
                  child: Text(_captchaChallenge!,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 4))))),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _logging ? null : _loginWithEmail,
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            child: _logging
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('登录 / 注册', style: TextStyle(fontSize: 16))),
          const SizedBox(height: 16),
          Text('第三方登录', style: TextStyle(fontSize: 14, color: cs.outline)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _buildLoginButton('assets/images/icons/wechat.png', '微信', () async {
              final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const WechatLoginPage()));
              _onAuthResult(r);
            })),
            const SizedBox(width: 12),
            Expanded(child: _buildLoginButton('assets/images/icons/qq.png', 'QQ', () async {
              final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const QQLoginPage()));
              _onAuthResult(r);
            })),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _buildLoginButton('assets/images/icons/telegram.png', 'Telegram', () async {
              final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const TelegramLoginPage()));
              _onAuthResult(r);
            })),
            const SizedBox(width: 12),
            Expanded(child: _buildLoginButton('assets/images/icons/douyin.png', '抖音', () async {
              final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const DouyinLoginPage()));
              _onAuthResult(r);
            })),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const BangumiLoginPage()));
                _onAuthResult(r);
              },
              icon: Image.asset('assets/images/icons/bangumi.png', width: 20, height: 20),
              label: const Text('Bangumi'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFED74A4),
                side: const BorderSide(color: Color(0xFFED74A4)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 🆕 换包名迁移：用旧 App 的迁移码直接继承登录态
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _importTransferCode,
              icon: const Icon(Icons.input, size: 20),
              label: const Text('我有迁移码'),
            ),
          ),
        ] else ...[
          // ========== 已登录：绑定状态列表 ==========
          _buildSectionTitle('账号绑定'),
          _buildStatusTile('assets/images/icons/wechat.png', '微信', _status['has_wechat']!, () async {
            if (_status['has_wechat']!) {
              _showUnbindDialog('wechat', '微信');
            } else {
              final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const WechatLoginPage(bindMode: true)));
              _onAuthResult(r);
            }
          }),
          _buildStatusTile('assets/images/icons/qq.png', 'QQ', _status['has_qq']!, () async {
            if (_status['has_qq']!) {
              _showUnbindDialog('qq', 'QQ');
            } else {
              final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const QQLoginPage(bindMode: true)));
              _onAuthResult(r);
            }
          }),
          _buildStatusTile('assets/images/icons/telegram.png', 'Telegram', _status['has_telegram']!, () async {
            if (_status['has_telegram']!) {
              _showUnbindDialog('telegram', 'Telegram');
            } else {
              final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const TelegramLoginPage(bindMode: true)));
              _onAuthResult(r);
            }
          }),
          _buildStatusTile('assets/images/icons/douyin.png', '抖音', _status['has_douyin'] ?? false, () async {
            if (_status['has_douyin'] ?? false) {
              _showUnbindDialog('douyin', '抖音');
            } else {
              final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const DouyinLoginPage(bindMode: true)));
              _onAuthResult(r);
            }
          }),
          _buildStatusTile('assets/images/icons/bangumi.png', 'Bangumi', _status['has_bangumi']!, () async {
            if (!_status['has_bangumi']!) {
              final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const BangumiLoginPage()));
              _onAuthResult(r);
            }
          }),
          _buildStatusTile(null, '邮箱', _status['has_email']!, () {
            if (!_status['has_email']!) _showBindEmailDialog();
          }),

          const SizedBox(height: 16),
          _buildSectionTitle('数据同步'),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _syncCollect,
              icon: const Icon(Icons.sync),
              label: Text(_syncing ? '同步中...' : '开始同步'),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices_rounded),
            title: const Text('登录设备管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeviceSessionsPage())),
          ),
          const SizedBox(height: 8),
          // 🆕 换包名迁移：给新 App 生成一次性迁移码
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('迁移到新 App（换包名）'),
              subtitle: const Text('生成 90 秒一次性迁移码，新 App 输入即可继承当前登录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showTransferDialog,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error),
            ),
          ),
          const SizedBox(height: 12),
          // 🆕 销毁账号：直接删除（后端已去掉 7 天冷静期）
          OutlinedButton.icon(
            onPressed: _deleteAccount,
            icon: const Icon(Icons.delete_forever),
            label: const Text('销毁账号'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildLoginButton(String iconPath, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Image.asset(iconPath, width: 20, height: 20),
      label: Text(label),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.outline)),
    );
  }

  Widget _buildStatusTile(String? iconPath, String name, bool isBound, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: iconPath != null ? Image.asset(iconPath, width: 28, height: 28) : const Icon(Icons.email),
        title: Text(name),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isBound ? Colors.green.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(isBound ? '已绑定' : '未绑定',
              style: TextStyle(fontSize: 12, color: isBound ? Colors.green.shade700 : Colors.grey)),
          ),
          const SizedBox(width: 4),
          Icon(isBound ? Icons.link_off : Icons.add, size: 18),
        ]),
        onTap: onTap,
      ),
    );
  }

  void _showUnbindDialog(String provider, String name) async {
    final confirm = await KazumiDialog.show<bool>(
      builder: (ctx) => AlertDialog(
        title: Text('解绑 $name'),
        content: Text('确定要解绑 $name 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('解绑', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final token = AuthService.getLocalToken();
        if (token == null) return;
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        final request = await client.postUrl(Uri.parse('https://qlyyz.xyz/api/v1/login?action=unbind_provider'));
        request.headers.set('Content-Type', 'application/json; charset=utf-8');
        request.headers.set('Authorization', 'Bearer $token');
        request.add(utf8.encode(jsonEncode({'provider': provider})));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        client.close();
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data['success'] == true) {
          await AccountStatusCache.clear();   // 🆕 缓存作废
          KazumiDialog.showToast(message: '$name 已解绑');
          await _loadStatus();
        } else {
          KazumiDialog.showToast(message: data['error'] ?? '解绑失败');
        }
      } catch (e) {
        KazumiDialog.showToast(message: '网络错误: $e');
      }
    }
  }

  void _showBindEmailDialog() {
    final emailCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    var challenge = <String>[];
    var sending = false;
    var binding = false;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('绑定邮箱'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'QQ 邮箱', hintText: 'xxx@qq.com', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: codeCtrl, keyboardType: TextInputType.number,
                maxLength: 6, decoration: const InputDecoration(labelText: '验证码', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: sending ? null : () async {
                  setDialogState(() => sending = true);
                  final res = await AuthService.sendCode(emailCtrl.text.trim());
                  setDialogState(() { sending = false; challenge = res['captcha_challenge'] != null ? [res['captcha_challenge'].toString()] : []; });
                  if (res['success'] == true) {
                    KazumiDialog.showToast(message: '验证码已发送，请查收邮箱（含垃圾箱）');
                  } else {
                    KazumiDialog.showToast(message: res['error'] ?? '发送失败');
                  }
                },
                child: Text(sending ? '发送中...' : '发送验证码')),
            ]),
            if (challenge.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextField(decoration: InputDecoration(labelText: '人机验证', border: const OutlineInputBorder(),
                suffixIcon: Padding(padding: const EdgeInsets.all(12), child: Text(challenge.first,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 4))))),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: binding ? null : () async {
              setDialogState(() => binding = true);
              final res = await AuthService.bindEmail(email: emailCtrl.text.trim(), code: codeCtrl.text.trim(),
                captchaAnswer: challenge.isEmpty ? '' : challenge.first);
              setDialogState(() => binding = false);
              if (res['success'] == true) {
                Navigator.pop(ctx);
                await AuthService.saveUserEmail(emailCtrl.text.trim());
                _loadStatus();
                AuthService.notifyLoginChanged();
                KazumiDialog.showToast(message: '邮箱绑定成功');
              } else {
                KazumiDialog.showToast(message: res['error'] ?? '绑定失败');
              }
            }, child: Text(binding ? '绑定中...' : '确认绑定')),
          ],
        ),
      ),
    );
  }
}

/// 邮箱登录页（复用已有的验证码登录逻辑）
class _EmailLoginPage extends StatefulWidget {
  const _EmailLoginPage();
  @override
  State<_EmailLoginPage> createState() => _EmailLoginPageState();
}

class _EmailLoginPageState extends State<_EmailLoginPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _captchaController = TextEditingController();
  bool _sending = false;
  bool _logging = false;
  String? _captchaChallenge;

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) { KazumiDialog.showToast(message: '请输入邮箱'); return; }
    setState(() => _sending = true);
    try {
      final res = await AuthService.sendCode(email);
      if (res['captcha_challenge'] != null) {
        setState(() => _captchaChallenge = res['captcha_challenge']);
        KazumiDialog.showToast(message: '验证码已发送');
      } else {
        KazumiDialog.showToast(message: res['error'] ?? '发送失败');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '网络错误: $e');
    }
    setState(() => _sending = false);
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final captcha = _captchaController.text.trim();
    if (code.length != 6) { KazumiDialog.showToast(message: '请输入6位验证码'); return; }
    setState(() => _logging = true);
    try {
      final res = await AuthService.login(email: email, code: code, captchaAnswer: captcha,
        deviceName: AuthService.currentDeviceName());
      if (res['token'] != null) {
        AuthService.saveLocalToken(res['token']);
        GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true); // 🆕 登录后自动开启同步
        await SocialService.ensureProfileAfterLogin();
        // 🆕 登录后把当前账号保存进「切换账号」列表（持久化）
        await AuthService.upsertCurrentAccount(
          nickname: SocialService.myProfile?.nickname,
          avatar: SocialService.myProfile?.avatar,
          uid: SocialService.myProfile?.uid,
        );
        if (res['user'] is Map && res['user']['email'] != null) {
          await AuthService.saveUserEmail(res['user']['email'].toString());
        }
        if (mounted) {
          setState(() => _logging = false);
          KazumiDialog.showToast(message: '登录成功');
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) { setState(() => _logging = false); KazumiDialog.showToast(message: res['error'] ?? '登录失败'); }
      }
    } catch (e) {
      if (mounted) { setState(() => _logging = false); KazumiDialog.showToast(message: '网络错误: $e'); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('邮箱登录')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 20),
        const Icon(Icons.email, size: 72),
        const SizedBox(height: 12),
        const Text('邮箱验证码登录', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 32),
        TextField(controller: _emailController, keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: '邮箱', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: TextField(controller: _codeController, maxLength: 6, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '验证码', border: OutlineInputBorder()))),
          const SizedBox(width: 12),
          FilledButton.tonal(onPressed: _sending ? null : _sendCode, child: _sending ? const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)) : const Text('发送')),
        ]),
        if (_captchaChallenge != null) ...[
          const SizedBox(height: 16),
          TextField(controller: _captchaController, maxLength: 6,
            decoration: InputDecoration(labelText: '人机验证', border: const OutlineInputBorder(),
              suffixIcon: Padding(padding: const EdgeInsets.all(12), child: Text(_captchaChallenge!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 4))))),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: _logging ? null : _login,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          child: _logging ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('登录 / 注册', style: TextStyle(fontSize: 17))),
      ]),
    );
  }
}

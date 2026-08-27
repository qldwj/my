import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
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
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  Map<String, bool> _status = {
    'has_qq': false, 'has_wechat': false, 'has_telegram': false,
    'has_douyin': false, 'has_bangumi': false, 'has_email': false,
  };

  @override
  void initState() {
    super.initState();
    _checkPendingLogin();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) { KazumiDialog.showToast(message: '请输入邮箱'); return; }
    setState(() => _sendingCode = true);
    try {
      final res = await AuthService.sendCode(email);
      if (res['captcha_challenge'] != null) {
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
    if (code.length != 6) { KazumiDialog.showToast(message: '请输入6位验证码'); return; }
    setState(() => _logging = true);
    try {
      final res = await AuthService.login(email: email, code: code, captchaAnswer: '',
        deviceName: AuthService.currentDeviceName());
      if (res['token'] != null) {
        AuthService.saveLocalToken(res['token']);
        GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
        await SocialService.ensureProfileAfterLogin();
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
    if (_loggedIn) _loadStatus(); // 只要已登录就加载状态
    if (mounted) setState(() {});
  }

  Future<void> _loadStatus() async {
    try {
      final token = AuthService.getLocalToken();
      if (token == null) return;
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(Uri.parse('https://qlyyz.xyz/api/login?action=login_status'));
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
      }
    } catch (e) {}
  }

  void _logout() {
    AuthService.clearLocalToken();
    SocialService.clearProfileCache();
    GStorage.putSetting(SettingsKeys.kazumiSyncEnable, false);
    setState(() {
      _loggedIn = false;
      _status = {'has_qq': false, 'has_wechat': false, 'has_telegram': false, 'has_douyin': false, 'has_bangumi': false, 'has_email': false};
    });
    KazumiDialog.showToast(message: '已退出登录');
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
          // ========== 未登录：邮箱登录 + 其他方式 ==========
          // 🆕 邮箱登录区域（直接在页面上）
          Text('验证码登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 4),
          Text('我们将发送一封验证码邮件', style: TextStyle(fontSize: 13, color: cs.outline)),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱', hintText: '你的QQ邮箱地址',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '验证码', counterText: '',
                border: OutlineInputBorder(), isDense: true),
            )),
            const SizedBox(width: 12),
            SizedBox(
              height: 48,
              child: FilledButton.tonal(
                onPressed: _sendingCode ? null : _sendCode,
                child: _sendingCode
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('获取验证码'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 48,
            child: FilledButton(
              onPressed: _logging ? null : _loginWithEmail,
              child: _logging
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('登录 / 注册', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 24),

          // 其他登录方式
          Text('其他登录方式', style: TextStyle(fontSize: 14, color: cs.outline)),
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
          // Bangumi
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
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BangumiLoginPage()));
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
        final request = await client.postUrl(Uri.parse('https://qlyyz.xyz/api/login?action=unbind_provider'));
        request.headers.set('Content-Type', 'application/json; charset=utf-8');
        request.headers.set('Authorization', 'Bearer $token');
        request.add(utf8.encode(jsonEncode({'provider': provider})));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        client.close();
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data['success'] == true) {
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

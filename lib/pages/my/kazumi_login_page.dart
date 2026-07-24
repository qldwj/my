import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';

/// 樱花动漫账号登录页（验证码登录，无需密码）
class KazumiLoginPage extends StatefulWidget {
  const KazumiLoginPage({super.key});

  @override
  State<KazumiLoginPage> createState() => _KazumiLoginPageState();
}

class _KazumiLoginPageState extends State<KazumiLoginPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _captchaController = TextEditingController();
  bool _sending = false;
  bool _logging = false;
  String? _captchaChallenge;
  bool _loggedIn = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loggedIn = AuthService.isLoggedIn;
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!email.endsWith('@qq.com')) {
      KazumiDialog.showToast(message: '请使用 QQ 邮箱');
      return;
    }
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
    if (code.length != 6) {
      KazumiDialog.showToast(message: '请输入6位验证码');
      return;
    }
    setState(() => _logging = true);
    try {
      final res = await AuthService.login(
        email: email,
        code: code,
        captchaAnswer: captcha,
      );
      if (res['token'] != null) {
        AuthService.saveLocalToken(res['token']);
        setState(() => _loggedIn = true);
        KazumiDialog.showToast(message: '登录成功 🎉');
        Navigator.of(context).pop(true);
      } else {
        KazumiDialog.showToast(message: res['error'] ?? '登录失败');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '网络错误: $e');
    }
    setState(() => _logging = false);
  }

  void _logout() {
    AuthService.clearLocalToken();
    setState(() => _loggedIn = false);
    KazumiDialog.showToast(message: '已退出登录');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('樱花动漫账号')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),
          Icon(Icons.person, size: 72, color: colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            _loggedIn ? '已登录 ✅' : '验证码登录',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (_loggedIn)
            Text(AuthService.getLocalToken() ?? '',
                style: TextStyle(fontSize: 11, color: colorScheme.outline)),
          const SizedBox(height: 32),

          if (!_loggedIn) ...[
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'QQ 邮箱',
                hintText: 'xxx@qq.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      hintText: '6位数字',
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _sending ? null : _sendCode,
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('发送'),
                ),
              ],
            ),

            if (_captchaChallenge != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _captchaController,
                decoration: InputDecoration(
                  labelText: '人机验证',
                  hintText: '请输入下方字符',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.verified_user),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _captchaChallenge!,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: colorScheme.primary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                maxLength: 6,
              ),
            ],

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _logging ? null : _login,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _logging
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('登录 / 注册', style: TextStyle(fontSize: 17)),
            ),
          ],

          if (_loggedIn) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.check_circle, size: 48, color: Colors.green),
                  SizedBox(height: 12),
                  Text('已登录', style: TextStyle(fontSize: 18)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Bangumi 绑定
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🎯 Bangumi 绑定',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (GStorage.getSetting(SettingsKeys.bangumiAccessToken)
                          .trim().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('已绑定',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.green.shade700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '绑定 Bangumi 后可同步追番列表和播放进度',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const _BangumiBindPage(),
                        ),
                      );
                    },
                    child: const Text('绑定 Bangumi'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 退出
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bangumi 绑定页面
class _BangumiBindPage extends StatefulWidget {
  const _BangumiBindPage();
  @override
  State<_BangumiBindPage> createState() => _BangumiBindPageState();
}

class _BangumiBindPageState extends State<_BangumiBindPage> {
  final _tokenController = TextEditingController();
  bool _binding = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _bind() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      KazumiDialog.showToast(message: '请输入 Bangumi Token');
      return;
    }
    setState(() => _binding = true);
    try {
      final res = await AuthService.bindBangumi(token);
      if (res['success'] == true) {
        await GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
        await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
        KazumiDialog.showToast(message: 'Bangumi 绑定成功 🎉');
        Navigator.of(context).pop();
      } else {
        KazumiDialog.showToast(message: res['error'] ?? '绑定失败');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '网络错误: $e');
    }
    setState(() => _binding = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasBangumi = GStorage.getSetting(SettingsKeys.bangumiAccessToken)
        .trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('绑定 Bangumi')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.link, size: 64),
          const SizedBox(height: 16),
          const Text('绑定 Bangumi 账号',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            hasBangumi ? '当前已绑定 Bangumi，可更新 Token' : '输入你的 Bangumi Access Token 完成绑定',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(
              labelText: 'Bangumi Access Token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _binding ? null : _bind,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: _binding
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('绑定'),
          ),
          if (hasBangumi) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                GStorage.putSetting(SettingsKeys.bangumiAccessToken, '');
                GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
                setState(() {});
                KazumiDialog.showToast(message: '已解除 Bangumi 绑定');
              },
              child: const Text('解除绑定', style: TextStyle(color: Colors.red)),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/sync/kazumi_sync_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/pages/my/qrcode_login_page.dart';
import 'package:kazumi/pages/my/device_sessions_page.dart';
import 'package:kazumi/pages/my/yhdmgz_qr_scan_page.dart';
import 'package:kazumi/pages/my/profile_edit_page.dart';

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
  bool _syncing = false;
  bool kazumiAutoSync = true;
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
    kazumiAutoSync =
        GStorage.getSetting<bool>(SettingsKeys.kazumiAutoSync);
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
        deviceName: AuthService.currentDeviceName(),
      );
      if (res['token'] != null) {
        AuthService.saveLocalToken(res['token']);
        // 🆕 登录后初始化社交资料（建号分配 uid/昵称/头像）并取消账号销毁
        await SocialService.ensureProfileAfterLogin();
        await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
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
    // 🔧 退出登录时清除社交资料缓存（避免切换账号残留上一账号头像/uid）
    SocialService.clearProfileCache();
    GStorage.putSetting(SettingsKeys.kazumiSyncEnable, false);
    setState(() => _loggedIn = false);
    KazumiDialog.showToast(message: '已退出登录');
  }

  /// 🆕 第三方登录（GitHub / QQ）；[bind] true 时为绑定当前账号
  Future<void> _startOAuth(String provider, {bool bind = false}) async {
    final bindToken = bind ? AuthService.getLocalToken() : null;
    final url =
        AuthService.oauthAuthorizeUrl(provider, bindToken: bindToken);
    try {
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok) {
        KazumiDialog.showToast(message: '无法打开浏览器，请检查系统设置');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '启动授权失败：$e');
    }
  }

  /// 🆕 OAuth 账号绑定邮箱弹窗（可选，绑定后改用真实邮箱登录）
  Future<void> _showBindEmailDialog() async {
    final emailCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    var challenge = <String>?[];
    var sending = false;
    var binding = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('绑定邮箱'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('绑定后可用邮箱+验证码登录，也可继续用 GitHub/QQ 登录（可选）',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'QQ 邮箱', hintText: 'xxx@qq.com',
                  border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: codeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                          labelText: '验证码', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: sending
                        ? null
                        : () async {
                            final email = emailCtrl.text.trim();
                            if (email.isEmpty) return;
                            setDialogState(() => sending = true);
                            final res = await AuthService.sendCode(email);
                            if (!ctx.mounted) return;
                            setDialogState(() {
                              sending = false;
                              challenge =
                                  (res['captcha_challenge'] as String?) == null
                                      ? null
                                      : [res['captcha_challenge'].toString()];
                            });
                          },
                    child: Text(sending ? '发送中...' : '发送验证码'),
                  ),
                ],
              ),
              if (challenge != null && challenge!.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    labelText: '人机验证',
                    hintText: challenge!.first,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.verified_user),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: binding
                  ? null
                  : () async {
                      setDialogState(() => binding = true);
                      final res = await AuthService.bindEmail(
                        email: emailCtrl.text.trim(),
                        code: codeCtrl.text.trim(),
                        captchaAnswer: challenge?.first ?? '',
                      );
                      if (!ctx.mounted) return;
                      setDialogState(() => binding = false);
                      if (res['success'] == true) {
                        Navigator.pop(ctx);
                        await AuthService.saveUserEmail(
                            emailCtrl.text.trim());
                        if (mounted) setState(() {});
                        KazumiDialog.showToast(message: '✅ 邮箱绑定成功');
                      } else {
                        KazumiDialog.showToast(
                            message: '❌ ${res['error'] ?? '绑定失败'}');
                      }
                    },
              child: Text(binding ? '绑定中...' : '确认绑定'),
            ),
          ],
        ),
      ),
    );
  }

  /// Token 脱敏：只保留头尾共 10 个字符，中间用星号代替
  String _maskToken(String token) {
    if (token.length <= 10) return token;
    return '${token.substring(0, 5)}'
        '${'*' * (token.length - 10)}'
        '${token.substring(token.length - 5)}';
  }

  /// 跳转到扫码页面（未登录时使用）
  void _gotoScan() {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const YhdmgzQrScanPage()),
    ).then((result) {
      // 扫码登录成功后刷新状态（不再 pop 本页，避免直接跳回首页）
      if (result == true) {
        // 延迟一下，确保 token 已经保存
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            final isLoggedIn = AuthService.isLoggedIn;
            setState(() {
              _loggedIn = isLoggedIn;
            });
            if (_loggedIn) {
              KazumiDialog.showToast(message: '扫码登录成功 🎉');
            }
          }
        });
      }
    });
  }

  /// 跳转到生成二维码页面（已登录时使用）
  void _gotoGenerateQr() {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const QrcodeLoginPage()),
    ).then((result) {
      if (result == true) {
        // 延迟一下，确保 token 已经保存
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            final isLoggedIn = AuthService.isLoggedIn;
            setState(() {
              _loggedIn = isLoggedIn;
            });
            if (_loggedIn) {
              KazumiDialog.showToast(message: '对方已扫码登录成功 🎉');
            }
          }
        });
      }
    });
  }

  /// 双向同步收藏
  Future<void> _syncCollect() async {
    setState(() => _syncing = true);
    try {
      await Future.any([
        _doSync(),
        Future.delayed(const Duration(seconds: 30), () => throw '同步超时，请检查网络'),
      ]);
    } catch (e) {
      KazumiDialog.dismiss();
      KazumiDialog.showToast(message: '❌ $e');
      KazumiLogger().e('同步失败', error: e);
    }
    setState(() => _syncing = false);
  }

  /// 核心同步逻辑
  Future<void> _doSync() async {
    try {
      KazumiDialog.showLoading(msg: '正在获取云端收藏...');
      final msg = await KazumiSyncService.syncCollect();
      KazumiDialog.dismiss();
      KazumiDialog.showToast(message: msg);
    } catch (e) {
      KazumiDialog.dismiss();
      KazumiDialog.showToast(message: '❌ 同步失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('樱花动漫账号'),
        actions: [
          // 🆕 编辑资料（笔头）：修改昵称 / 头像
          if (_loggedIn)
            IconButton(
              key: const ValueKey('edit_profile'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileEditPage()),
              ),
              icon: const Icon(Icons.edit_rounded),
              tooltip: '编辑资料',
            ),
          IconButton(
            key: ValueKey(_loggedIn ? 'qr_generate' : 'qr_scan'),
            onPressed: _loggedIn ? _gotoGenerateQr : _gotoScan,
            icon: Icon(
              _loggedIn ? Icons.qr_code : Icons.qr_code_scanner,
              // 白色在粉色主题下不明显，改用主题暗色前景色
              color: colorScheme.onSurface,
            ),
            tooltip: _loggedIn ? '生成登录二维码' : '扫描二维码登录',
          ),
        ],
      ),
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
            Text(_maskToken(AuthService.getLocalToken() ?? ''),
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
            const SizedBox(height: 20),
            // 🆕 第三方登录（GitHub / QQ，聚合登录）
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _logging ? null : () => _startOAuth('github'),
                    icon: const Icon(Icons.code_rounded),
                    label: const Text('GitHub 登录'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _logging ? null : () => _startOAuth('qq'),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('QQ 登录'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '通过 GitHub / QQ 登录即自动注册',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
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

            // 樱花同步按钮
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sync, size: 20),
                      SizedBox(width: 8),
                      Text('收藏同步', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '将追番列表同步到樱花服务器，双向合并',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _syncCollect,
                      icon: const Icon(Icons.sync),
                      label: Text(_syncing ? '同步中...' : '开始同步'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 自动同步开关（默认开启，30 分钟一次）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SwitchListTile(
                value: kazumiAutoSync,
                onChanged: (value) async {
                  setState(() => kazumiAutoSync = value);
                  await GStorage.putSetting<bool>(
                      SettingsKeys.kazumiAutoSync, value);
                },
                title: const Text('自动同步'),
                subtitle: const Text('登录后每 30 分钟自动同步收藏'),
              ),
            ),
            const SizedBox(height: 12),
            // 🆕 登录设备管理
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.devices_rounded),
                title: const Text('登录设备管理'),
                subtitle: const Text('查看已登录设备，可踢下线'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DeviceSessionsPage()),
                ),
              ),
            ),
            const SizedBox(height: 16),

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
            const SizedBox(height: 12),
            // 🆕 OAuth 账号：绑定邮箱（可选，可用真实邮箱登录）
            if (AuthService.isOAuthAccount) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showBindEmailDialog,
                  icon: const Icon(Icons.alternate_email_rounded),
                  label: const Text('绑定邮箱（改用邮箱登录）'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 🆕 绑定 GitHub / QQ（一个账号只能绑一个，二选一）
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _startOAuth('github', bind: true),
                    icon: const Icon(Icons.code_rounded),
                    label: const Text('绑定 GitHub'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _startOAuth('qq', bind: true),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('绑定 QQ'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),const SizedBox(height: 12),

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
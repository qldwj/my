import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';

/// QQ OAuth 登录页
class QQLoginPage extends StatefulWidget {
  const QQLoginPage({super.key});
  @override
  State<QQLoginPage> createState() => _QQLoginPageState();
}

class _QQLoginPageState extends State<QQLoginPage> {
  static const String _oauthUrl = 'https://qlyyz.xyz/api/oauth_login.php?action=login&provider=qq';
  static const String _verifyUrl = 'https://qlyyz.xyz/api/login?action=verify_app_token';

  StreamSubscription<Uri>? _linkSub;
  final _appLinks = AppLinks();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'yhdmgz' && uri.host == 'qq-auth') {
        final appToken = uri.queryParameters['token'];
        if (appToken != null && appToken.isNotEmpty) _verifyToken(appToken);
      }
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _verifyToken(String appToken) async {
    setState(() => _loading = true);
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.postUrl(Uri.parse(_verifyUrl));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode(jsonEncode({
        'app_token': appToken,
        'device_name': AuthService.currentDeviceName(),
      })));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['token'] != null) {
        AuthService.saveLocalToken(data['token']);
        final user = data['user'];
        if (user is Map && user['email'] != null) {
          await AuthService.saveUserEmail(user['email'].toString());
        }
        await SocialService.ensureProfileAfterLogin();
        if (mounted) {
          setState(() => _loading = false);
          KazumiDialog.showToast(message: 'QQ 登录成功 🎉');
          Navigator.of(context).pop(true);
        }
      } else if (mounted) {
        setState(() => _loading = false);
        KazumiDialog.showToast(message: data['error'] ?? '登录失败');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        KazumiDialog.showToast(message: '网络错误: $e');
      }
    }
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(_oauthUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    } catch (e) {
      KazumiDialog.showToast(message: '打开授权页失败: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('QQ 登录')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        Container(width: 80, height: 80,
          decoration: BoxDecoration(color: const Color(0xFF12B7F5).withAlpha(25), shape: BoxShape.circle),
          child: const Image.asset('assets/images/icons/qq.png', width: 40, height: 40)),
        const SizedBox(height: 20),
        const Text('QQ 授权登录', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('点击下方按钮，跳转到 QQ 授权页面', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 40),
        FilledButton(onPressed: _loading ? null : _login,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50),
            backgroundColor: const Color(0xFF12B7F5)),
          child: _loading ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('打开 QQ 授权', style: TextStyle(fontSize: 17))),
        const SizedBox(height: 16),
        Text('授权后会自动跳回 App 完成登录', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: cs.outline)),
      ]),
    );
  }
}

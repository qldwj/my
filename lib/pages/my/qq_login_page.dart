import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';

/// QQ OAuth 登录/绑定页
/// [bindMode] = true 时为绑定模式（已有邮箱账号绑定 QQ）
class QQLoginPage extends StatefulWidget {
  final bool bindMode;
  const QQLoginPage({super.key, this.bindMode = false});
  @override
  State<QQLoginPage> createState() => _QQLoginPageState();
}

class _QQLoginPageState extends State<QQLoginPage> {
  static const String _verifyUrl = 'https://qlyyz.xyz/api/login?action=verify_app_token';
  static const String _bindUrl = 'https://qlyyz.xyz/api/login?action=bind_provider';

  StreamSubscription<Uri>? _linkSub;
  final _appLinks = AppLinks();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'yhdm' && uri.host == 'qq-auth') {
        final appToken = uri.queryParameters['token'];
        if (appToken != null && appToken.isNotEmpty) {
          widget.bindMode ? _bindToken(appToken) : _verifyToken(appToken);
        }
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
      request.add(utf8.encode(jsonEncode({'app_token': appToken, 'device_name': AuthService.currentDeviceName()})));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;

      // 🆕 绑定模式：服务器返回 bind_mode，调用 bind_provider 完成绑定
      if (data['bind_mode'] == true) {
        final bindProvider = data['provider'] ?? '';
        final bindToken = data['app_token'] ?? '';
        if (bindProvider.isNotEmpty && bindToken.isNotEmpty) {
          final currentToken = AuthService.getLocalToken();
          if (currentToken != null) {
            final bindClient = HttpClient();
            bindClient.connectionTimeout = const Duration(seconds: 15);
            final bindReq = await bindClient.postUrl(Uri.parse(_bindUrl));
            bindReq.headers.set('Content-Type', 'application/json; charset=utf-8');
            bindReq.headers.set('Authorization', 'Bearer $currentToken');
            bindReq.add(utf8.encode(jsonEncode({'provider': bindProvider, 'app_token': bindToken})));
            final bindRes = await bindReq.close();
            final bindBody = await bindRes.transform(utf8.decoder).join();
            bindClient.close();
            final bindData = jsonDecode(bindBody) as Map<String, dynamic>;
            if (mounted) {
              setState(() => _loading = false);
              if (bindData['success'] == true) {
                KazumiDialog.showToast(message: '绑定成功');
              } else {
                KazumiDialog.showToast(message: bindData['error'] ?? '绑定失败');
              }
              Navigator.of(context).pop(true);
            }
            return;
          }
        }
      }

      // 登录模式
      if (data['token'] != null) {
        AuthService.saveLocalToken(data['token']);
        GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
        final user = data['user'];
        if (user is Map && user['email'] != null) await AuthService.saveUserEmail(user['email'].toString());
        if (mounted) {
          setState(() => _loading = false);
          KazumiDialog.showToast(message: '登录成功');
          Navigator.of(context).pop(true);
        }
      } else if (mounted) {
        setState(() => _loading = false);
        KazumiDialog.showToast(message: data['error'] ?? '登录失败');
      }
    } catch (e) {
      if (mounted) { setState(() => _loading = false); KazumiDialog.showToast(message: '网络错误: $e'); }
    }
  }

  Future<void> _bindToken(String appToken) async {
    setState(() => _loading = true);
    try {
      final token = AuthService.getLocalToken();
      if (token == null) { KazumiDialog.showToast(message: '未登录'); return; }
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.postUrl(Uri.parse(_bindUrl));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $token');
      request.add(utf8.encode(jsonEncode({'provider': 'qq', 'app_token': appToken})));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['success'] == true) {
        if (mounted) {
          setState(() => _loading = false);
          KazumiDialog.showToast(message: 'QQ 绑定成功 🎉');
          Navigator.of(context).pop(true);
        }
      } else if (mounted) {
        setState(() => _loading = false);
        KazumiDialog.showToast(message: data['error'] ?? '绑定失败');
      }
    } catch (e) {
      if (mounted) { setState(() => _loading = false); KazumiDialog.showToast(message: '网络错误: $e'); }
    }
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final bindParam = widget.bindMode ? '&bind=1' : '';
      final uri = Uri.parse('https://qlyyz.xyz/api/oauth_login.php?action=login&provider=qq$bindParam');
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      KazumiDialog.showToast(message: '打开授权页失败: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.bindMode ? '绑定 QQ' : 'QQ 登录')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        Container(width: 80, height: 80,
          decoration: BoxDecoration(color: const Color(0xFF12B7F5).withAlpha(25), shape: BoxShape.circle),
          child: Image.asset('assets/images/icons/qq.png', width: 40, height: 40)),
        const SizedBox(height: 20),
        Text(widget.bindMode ? '绑定 QQ 账号' : 'QQ 授权登录',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(widget.bindMode ? '授权后 QQ 将绑定到当前账号' : '点击下方按钮，跳转到 QQ 授权页面',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 40),
        FilledButton(onPressed: _loading ? null : _login,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50),
            backgroundColor: const Color(0xFF12B7F5)),
          child: _loading ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(widget.bindMode ? '打开 QQ 授权绑定' : '打开 QQ 授权', style: const TextStyle(fontSize: 17))),
        const SizedBox(height: 16),
        Text('授权后会自动跳回 App 完成${widget.bindMode ? "绑定" : "登录"}',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.outline)),
      ]),
    );
  }
}

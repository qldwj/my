import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/services/auth_service.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/storage/settings_keys.dart';
import 'package:url_launcher/url_launcher.dart';

/// 抖音 OAuth 登录/绑定页
class DouyinLoginPage extends StatefulWidget {
  final bool bindMode;
  const DouyinLoginPage({super.key, this.bindMode = false});
  @override
  State<DouyinLoginPage> createState() => _DouyinLoginPageState();
}

class _DouyinLoginPageState extends State<DouyinLoginPage> {
  static const String _verifyUrl = 'https://qlyyz.xyz/api/v1/login?action=verify_app_token';
  static const String _bindUrl = 'https://qlyyz.xyz/api/v1/login?action=bind_provider';

  StreamSubscription<Uri>? _linkSub;
  final _appLinks = AppLinks();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'yhdm' && uri.host == 'dy-auth') {
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

  /// 🆕 带空体容错 + 自动重试的 POST JSON
  /// 解决慢网/响应被截断导致的 "FormatException: Unexpected end of input"（jsonDecode 空串）
  Future<Map<String, dynamic>?> _postJson(
    String url,
    Map<String, dynamic> body, {
    String? bearer,
    int retries = 2,
  }) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      client.userAgent =
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
      try {
        final req = await client.postUrl(Uri.parse(url));
        req.headers.set('Content-Type', 'application/json; charset=utf-8');
        if (bearer != null && bearer.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $bearer');
        }
        req.add(utf8.encode(jsonEncode(body)));
        final res = await req.close();
        final raw = await res.transform(utf8.decoder).join();
        client.close();
        if (raw.trim().isEmpty) {
          // 空体：慢网被截断，重试
          if (attempt < retries) {
            await Future.delayed(const Duration(milliseconds: 600));
            continue;
          }
          return {'success': false, 'error': '网络异常，响应为空，请重试'};
        }
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return {'success': false, 'error': '响应格式异常'};
      } catch (_) {
        client.close();
        if (attempt < retries) {
          await Future.delayed(const Duration(milliseconds: 600));
          continue;
        }
        rethrow;
      }
    }
    return null;
  }

  Future<void> _verifyToken(String appToken) async {
    setState(() => _loading = true);
    try {
      final data = await _postJson(_verifyUrl, {
        'app_token': appToken,
        'device_name': AuthService.currentDeviceName(),
      });
      if (data == null) {
        if (mounted) { setState(() => _loading = false); KazumiDialog.showToast(message: '登录失败，请重试'); }
        return;
      }

      // 🆕 绑定模式：服务器返回 bind_mode，调用 bind_provider 完成绑定
      if (data['bind_mode'] == true) {
        final bindProvider = data['provider'] ?? '';
        final bindToken = data['app_token'] ?? '';
        if (bindProvider.isNotEmpty && bindToken.isNotEmpty) {
          final currentToken = AuthService.getLocalToken();
          if (currentToken != null) {
            final bindData = await _postJson(_bindUrl, {
              'provider': bindProvider,
              'app_token': bindToken,
            }, bearer: currentToken);
            if (mounted) {
              setState(() => _loading = false);
              if (bindData != null && bindData['success'] == true) {
                KazumiDialog.showToast(message: '绑定成功');
              } else {
                KazumiDialog.showToast(message: bindData?['error'] ?? '绑定失败');
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
      if (mounted) { setState(() => _loading = false); KazumiDialog.showToast(message: '网络错误，请重试'); }
    }
  }

  Future<void> _bindToken(String appToken) async {
    setState(() => _loading = true);
    try {
      final token = AuthService.getLocalToken();
      if (token == null) { KazumiDialog.showToast(message: '未登录'); return; }
      final data = await _postJson(_bindUrl, {
        'provider': 'douyin',
        'app_token': appToken,
      }, bearer: token);
      if (data == null) {
        if (mounted) { setState(() => _loading = false); KazumiDialog.showToast(message: '绑定失败，请重试'); }
        return;
      }
      if (data['success'] == true) {
        if (mounted) {
          setState(() => _loading = false);
          KazumiDialog.showToast(message: '抖音绑定成功');
          AuthService.notifyLoginChanged();
          Navigator.of(context).pop(true);
        }
      } else if (mounted) {
        setState(() => _loading = false);
        KazumiDialog.showToast(message: data['error'] ?? '绑定失败');
      }
    } catch (e) {
      if (mounted) { setState(() => _loading = false); KazumiDialog.showToast(message: '网络错误，请重试'); }
    }
  }

  // 🆕 主登录：应用内浏览器打开授权页（之前的格式）
  Future<void> _login() async {
    await _open(mode: LaunchMode.inAppBrowserView);
  }

  // 🆕 兜底：内置浏览器打不开时，点下方按钮跳外部浏览器
  Future<void> _openExternal() async {
    await _open(mode: LaunchMode.externalApplication);
  }

  Future<void> _open({required LaunchMode mode}) async {
    setState(() => _loading = true);
    try {
      final bindParam = widget.bindMode ? '&bind=1' : '';
      final uri = Uri.parse('https://qlyyz.xyz/api/v1/oauth_login.php?action=login&provider=douyin$bindParam');
      final ok = await launchUrl(uri, mode: mode);
      if (!ok && mounted) {
        KazumiDialog.showToast(message: '应用内浏览器打开失败，请点下方按钮改用外部浏览器');
      }
    } catch (e) {
      if (mounted) {
        KazumiDialog.showToast(message: '打开授权页失败，请点下方按钮改用外部浏览器');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.bindMode ? '绑定抖音' : '抖音登录')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        Container(width: 80, height: 80,
          decoration: BoxDecoration(color: const Color(0xFF000000).withAlpha(25), shape: BoxShape.circle),
          child: Image.asset('assets/images/icons/douyin.png', width: 40, height: 40)),
        const SizedBox(height: 20),
        Text(widget.bindMode ? '绑定抖音账号' : '抖音授权登录',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(widget.bindMode ? '授权后抖音将绑定到当前账号' : '点击下方按钮，跳转到抖音授权页面',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 40),
        FilledButton(onPressed: _loading ? null : _login,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: const Color(0xFF000000)),
          child: _loading ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(widget.bindMode ? '打开抖音授权绑定' : '打开抖音授权', style: const TextStyle(fontSize: 17))),
        const SizedBox(height: 12),
        // 🆕 兜底按钮：应用内浏览器打不开时，点我跳外部浏览器
        InkWell(
          onTap: _loading ? null : _openExternal,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('如果无法打开浏览器，点击我',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.outline, decoration: TextDecoration.underline)),
          ),
        ),
        const SizedBox(height: 8),
        Text('授权后会自动跳回 App 完成${widget.bindMode ? "绑定" : "登录"}',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.outline)),
      ]),
    );
  }
}

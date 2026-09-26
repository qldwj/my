import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 网页版授权登录（App 端）
///
/// 流程：
///   1. 网页跳转 `yhdmgz://auth?redirect=<回跳地址>&state=<随机串>&app=<应用名>`
///   2. App 收到深链 → 检查是否已登录
///   3. 已登录 → 弹「授权」对话框，用户同意后向服务端申请一次性 code
///   4. App 跳回浏览器 `redirect?code=xxx&state=yyy`
///   5. 网页后端用 code 换 token（服务端对服务端，token 不经过 URL）
///
/// 安全要点：
///   - 只传一次性 code（60 秒有效，用过即废），不传 token
///   - state 原样回传，由网页端校验（防 CSRF）
///   - 必须用户手动点「同意」
class WebAuthService {
  WebAuthService._();

  /// 申请一次性授权码（需要已登录）
  ///
  /// 返回 `{success: true, code: 'xxx'}` 或 `{success: false, error: '...'}`
  static Future<Map<String, dynamic>> requestCode({
    required String state,
    String appName = '',
  }) async {
    final token = AuthService.getLocalToken();
    if (token == null || token.isEmpty) {
      return {'success': false, 'error': '未登录'};
    }
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 12);
      final req = await client.postUrl(
          Uri.parse('https://qlyyz.xyz/api/webauth.php?action=create'));
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.set('Authorization', 'Bearer $token');
      req.add(utf8.encode(jsonEncode({
        'state': state,
        'app': appName,
      })));
      final resp = await req.close().timeout(const Duration(seconds: 12));
      final text = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));
      client.close(force: true);
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (e) {
      KazumiLogger().w('WebAuth: 申请授权码失败', error: e);
      return {'success': false, 'error': '网络异常'};
    }
  }

  /// 解析网页授权深链
  ///
  /// `yhdmgz://auth?redirect=xxx&state=yyy&app=zzz`
  static WebAuthRequest? parse(String url) {
    try {
      final uri = Uri.parse(url.trim());
      if (uri.scheme != 'yhdmgz' || uri.host != 'auth') return null;
      final redirect = uri.queryParameters['redirect'];
      if (redirect == null || redirect.isEmpty) return null;
      return WebAuthRequest(
        redirect: redirect,
        state: uri.queryParameters['state'] ?? '',
        appName: uri.queryParameters['app'] ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// 构造回跳 URL（带 code + state）
  static String buildCallback({
    required String redirect,
    required String code,
    required String state,
  }) {
    final uri = Uri.parse(redirect);
    final params = Map<String, String>.from(uri.queryParameters);
    params['code'] = code;
    if (state.isNotEmpty) params['state'] = state;
    return uri.replace(queryParameters: params).toString();
  }

  /// 构造失败回跳 URL
  static String buildErrorCallback({
    required String redirect,
    required String error,
    required String state,
  }) {
    final uri = Uri.parse(redirect);
    final params = Map<String, String>.from(uri.queryParameters);
    params['error'] = error;
    if (state.isNotEmpty) params['state'] = state;
    return uri.replace(queryParameters: params).toString();
  }
}

class WebAuthRequest {
  const WebAuthRequest({
    required this.redirect,
    this.state = '',
    this.appName = '',
  });

  final String redirect;
  final String state;
  final String appName;
}

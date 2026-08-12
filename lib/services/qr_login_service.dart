
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 樱花动漫扫码登录 PHP 后端版
/// qlyyz.xyz/api/qr/
class QrLoginService {

  static const String base =
      "https://qlyyz.xyz/api/qr/";

  static const String scheme = "yhdmgz";

  /// 网络超时：连接超时 10s，整体请求超时 20s。
  /// 避免服务器不响应时，扫码页一直卡在"登录中..."的加载状态。
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _requestTimeout = Duration(seconds: 20);


  static bool canHandle(String value) {
    try {
      final uri = Uri.parse(value);
      return uri.scheme == scheme &&
          uri.host == "login";
    } catch (_) {
      return false;
    }
  }


  /// 从 yhdmgz://login 链接中提取二维码会话码。
  /// 兼容 `?code=xxx` 与 `?token=xxx` 两种写法（历史代码两种都在用）。
  static String? getCode(String value) {
    try {
      final uri = Uri.parse(value);

      if (!canHandle(value)) return null;

      final code = uri.queryParameters["code"];
      if (code != null && code.isNotEmpty) return code;

      final token = uri.queryParameters["token"];
      if (token != null && token.isNotEmpty) return token;

      return null;
    } catch (_) {
      return null;
    }
  }


  /// 兼容旧页面命名（与 getCode 等价）
  static String? getToken(String value) => getCode(value);


  /// 已登录设备生成二维码数据
  /// [userToken]：机主（展示二维码的已登录设备）的 token，
  /// 后端将其存入会话，用于区分"机主确认"与"扫码者请求"。
  static Future<Map<String,dynamic>> createQr({String userToken = ''}) async {
    try {
      final data = await _post("${base}create.php", {
        "token": userToken,
      });
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'error': '服务器响应格式错误'};
    } catch (e) {
      return {'error': '创建二维码失败: $e'};
    }
  }


  /// 扫码设备确认登录（或已登录设备同意确认）
  /// 返回完整的服务端响应，便于调用方提取 token / 错误信息。
  static Future<Map<String,dynamic>> confirmLogin(
      String code,
      String userToken
  ) async {
    try {
      final data = await _post("${base}confirm.php", {
        "code": code,
        "token": userToken,
      });
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': false, 'error': '服务器响应格式错误'};
    } catch (e) {
      return {'success': false, 'error': '网络连接失败: $e'};
    }
  }



  /// 被登录设备轮询状态
  static Future<Map<String,dynamic>> check(
      String code
  ) async {
    try {
      final data = await _get(
        "${base}check.php?code=${Uri.encodeQueryComponent(code)}",
      );
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'error': '服务器响应格式错误'};
    } catch (e) {
      return {'error': '网络连接失败: $e'};
    }
  }


  /// 兼容旧页面：扫码后直接确认登录（不弹确认框），返回是否成功
  static Future<bool> directLogin(String code) async {
    final result = await confirmLogin(code, '');
    return result['success'] == true ||
        result['status'] == 'confirmed' ||
        result['status'] == 'success';
  }


  /// 扫码设备在"等待机主确认"后轮询 check.php，
  /// 直到机主确认（status=success，返回机主 token）或二维码过期。
  static Future<Map<String,dynamic>> waitForLogin(
    String code, {
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(interval);
      final data = await check(code);
      final status = data['status'];
      if (status == 'success' || status == 'expired' || status == 'error') {
        return data;
      }
    }
    return {'status': 'expired', 'error': '等待机主确认超时，请重新扫码'};
  }


  // ============ 带超时的统一网络封装 ============

  static Future<dynamic> _post(
    String url,
    Map<String, dynamic>? body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = _connectTimeout;
    try {
      final request = await client.postUrl(Uri.parse(url));
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request
          .close()
          .timeout(_requestTimeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}: $text');
      }
      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }

  static Future<dynamic> _get(String url) async {
    final client = HttpClient()
      ..connectionTimeout = _connectTimeout;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request
          .close()
          .timeout(_requestTimeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}: $text');
      }
      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }
}

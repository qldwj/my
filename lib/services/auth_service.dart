import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';

/// 自定义登录/注册服务
///
/// 后端签名方式与搜索接口一致：
///   X-AppId: KAZUMI_APPID
///   X-Timestamp: 当前时间戳
///   X-Signature: base64(sha256(appId + timestamp + body + secret))
class AuthService {
  static const String baseUrl = 'https://qlyyz.xyz/login.php';

  static String get _appId => bangumiMirrorCredentials['id'] ?? '';
  static String get _appKey => bangumiMirrorCredentials['value'] ?? '';

  /// 生成签名
  static String _sign(String body, int timestamp) {
    final data = utf8.encode('$_appId$timestamp$body$_appKey');
    final digest = sha256.convert(data);
    return base64Encode(digest.bytes);
  }

  /// 发送请求
  static Future<Map<String, dynamic>> _request(
    String action,
    Map<String, dynamic> body,
  ) async {
    final bodyStr = jsonEncode(body);
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.postUrl(Uri.parse('$baseUrl?action=$action'));
      
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-AppId', _appId);
      request.headers.set('X-Timestamp', timestamp.toString());
      request.headers.set('X-Signature', _sign(bodyStr, timestamp));
      request.write(bodyStr);
      
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();
      
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (e) {
      KazumiLogger().e('AuthService: 请求失败', error: e);
      return {'error': '网络连接失败'};
    }
  }

  /// 发送验证码
  static Future<Map<String, dynamic>> sendCode(String email) {
    return _request('send_code', {'email': email});
  }

  /// 注册（验证码即身份，无需密码）
  static Future<Map<String, dynamic>> register({
    required String email,
    required String code,
    required String captchaAnswer,
  }) {
    return _request('register', {
      'email': email,
      'code': code,
      'captcha_answer': captchaAnswer,
    });
  }

  /// 登录（验证码即身份，无需密码）
  static Future<Map<String, dynamic>> login({
    required String email,
    required String code,
    required String captchaAnswer,
  }) {
    return _request('login', {
      'email': email,
      'code': code,
      'captcha_answer': captchaAnswer,
    });
  }

  /// 获取用户信息
  static Future<Map<String, dynamic>> getUser(String token) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final bodyStr = '';

      final request = await client.getUrl(Uri.parse('$baseUrl?action=user'));
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.set('X-AppId', _appId);
      request.headers.set('X-Timestamp', timestamp.toString());
      request.headers.set('X-Signature', _sign(bodyStr, timestamp));
      
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (e) {
      KazumiLogger().e('AuthService: 获取用户失败', error: e);
      return {'error': '网络连接失败'};
    }
  }

  /// 获取本地保存的 token
  static String? getLocalToken() {
    final token = GStorage.getSetting(SettingsKeys.kazumiToken);
    return (token as String?)?.isNotEmpty == true ? token as String : null;
  }

  /// 保存 token 到本地
  static void saveLocalToken(String token) {
    GStorage.putSetting(SettingsKeys.kazumiToken, token);
  }

  /// 清除本地 token
  static void clearLocalToken() {
    GStorage.putSetting(SettingsKeys.kazumiToken, '');
  }

  /// 是否已登录自定义账号
  static bool get isLoggedIn => getLocalToken() != null;
}

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';

/// 自定义登录/注册服务
class AuthService {
  static const String baseUrl = 'https://qlyyz.xyz/api/login';

  static String get _appId => bangumiMirrorCredentials['id'] ?? '';
  static String get _appKey => bangumiMirrorCredentials['value'] ?? '';

  static String _sign(String body, int timestamp) {
    final data = utf8.encode('$_appId$timestamp$body$_appKey');
    final digest = sha256.convert(data);
    return base64Encode(digest.bytes);
  }

  /// 统一 HTTP 请求（支持可选 Bearer Token）
  static Future<Map<String, dynamic>> _request(
    String action,
    Map<String, dynamic> body, {
    String? authToken,
    bool skipSignature = false,
  }) async {
    final bodyStr = jsonEncode(body);
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      final request = await client.postUrl(Uri.parse('$baseUrl?action=$action'));

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      if (authToken != null) {
        request.headers.set('Authorization', 'Bearer $authToken');
      }
      if (!skipSignature) {
        request.headers.set('X-AppId', _appId);
        request.headers.set('X-Timestamp', timestamp.toString());
        request.headers.set('X-Signature', _sign(bodyStr, timestamp));
      }
      request.add(utf8.encode(bodyStr));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode != 200) {
        try {
          final errData = jsonDecode(responseBody) as Map<String, dynamic>;
          return {'error': errData['error'] ?? 'HTTP ${response.statusCode}'};
        } catch (_) {
          return {'error': 'HTTP ${response.statusCode}: $responseBody'};
        }
      }
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (e) {
      KazumiLogger().e('AuthService: 请求失败', error: e);
      return {'error': '网络连接失败: $e'};
    }
  }

  /// 发送验证码
  static Future<Map<String, dynamic>> sendCode(String email) {
    return _request('send_code', {'email': email});
  }

  /// 注册
  static Future<Map<String, dynamic>> register({
    required String email,
    required String code,
    required String captchaAnswer,
  }) async {
    final res = await _request('register', {
      'email': email,
      'code': code,
      'captcha_answer': captchaAnswer,
    });
    if (res['bangumi_token'] is String && (res['bangumi_token'] as String).isNotEmpty) {
      await GStorage.putSetting(SettingsKeys.bangumiAccessToken, res['bangumi_token'] as String);
      await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
    }
    return res;
  }

  /// 登录
  static Future<Map<String, dynamic>> login({
    required String email,
    required String code,
    required String captchaAnswer,
  }) async {
    final res = await _request('login', {
      'email': email,
      'code': code,
      'captcha_answer': captchaAnswer,
    });
    if (res['bangumi_token'] is String && (res['bangumi_token'] as String).isNotEmpty) {
      await GStorage.putSetting(SettingsKeys.bangumiAccessToken, res['bangumi_token'] as String);
      await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
    }
    return res;
  }

  /// 同步数据（收藏/历史/进度）——type: collect | history | progress
  static Future<Map<String, dynamic>> syncData(
    Map<String, dynamic> data, {
    String type = 'collect',
  }) async {
    final token = getLocalToken();
    if (token == null) return {'error': '未登录'};
    return _request('sync', {'type': type, 'data': data},
        authToken: token, skipSignature: true);
  }

  /// 🆕 一次性拉取全部云端数据（收藏/历史/进度）
  static Future<Map<String, dynamic>> getRemoteSync() async {
    final token = getLocalToken();
    if (token == null) return {'error': '未登录'};
    return _request('get_sync', {}, authToken: token, skipSignature: true);
  }

  /// 🆕 只读获取云端收藏（调用后端专用的 `get_collect` 接口，不会修改服务器数据）
  static Future<Map<String, dynamic>> getRemoteCollect() async {
    final token = getLocalToken();
    if (token == null) return {'error': '未登录'};
    return _request('get_collect', {}, authToken: token, skipSignature: true);
  }

  /// ⚠️ 已弃用：此方法会因传入空列表而清空服务器数据，请改用 `getRemoteCollect()`
  @Deprecated('使用 getRemoteCollect() 替代，此方法会清空服务器数据')
  static Future<Map<String, dynamic>> fetchRemoteCollect() async {
    final token = getLocalToken();
    if (token == null) return {'error': '未登录'};
    return _request('sync', {'data': {'collect': []}}, authToken: token, skipSignature: true);
  }

  /// 绑定 Bangumi
  static Future<Map<String, dynamic>> bindBangumi(String bangumiToken) async {
    final token = getLocalToken();
    if (token == null) return {'error': '未登录'};
    return _request('bind_bangumi', {'bangumi_token': bangumiToken},
        authToken: token, skipSignature: true);
  }

  /// 获取用户信息（GET）
  static Future<Map<String, dynamic>> getUser(String token) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse('$baseUrl?action=user'));
      request.headers.set('Authorization', 'Bearer $token');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      KazumiLogger().e('AuthService: 获取用户失败', error: e);
      return {'error': '网络连接失败'};
    }
  }

  /// ⭐ 二维码登录（扫描后直接登录）
  static Future<Map<String, dynamic>> qrcodeLogin(String token) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.postUrl(
        Uri.parse('$baseUrl?action=qrcode_login'),
      );
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      
      final body = jsonEncode({'token': token, 'confirm': true});
      request.write(body);
      
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();
      
      if (response.statusCode != 200) {
        return {'error': 'HTTP ${response.statusCode}'};
      }
      
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      return data;
    } catch (e) {
      KazumiLogger().e('AuthService: 二维码登录失败', error: e);
      return {'error': '网络连接失败: $e'};
    }
  }

  static String? getLocalToken() {
    final token = GStorage.getSetting(SettingsKeys.kazumiToken);
    return (token as String?)?.isNotEmpty == true ? token as String : null;
  }

  static void saveLocalToken(String token) {
    GStorage.putSetting(SettingsKeys.kazumiToken, token);
  }

  static void clearLocalToken() {
    GStorage.putSetting(SettingsKeys.kazumiToken, '');
  }

  static bool get isLoggedIn => getLocalToken() != null;
}
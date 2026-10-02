import 'dart:convert';
import 'dart:io';

import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 🆕 公开个人主页 / 好友关注客户端
///
/// 对接后端 api/u.php：
/// - GET  ?uid=    → 公开主页数据（含我是否已关注 followedByMe）
/// - POST follow / unfollow / status（Bearer token）
class FriendService {
  FriendService._();

  static const String api = ApiEndpoints.publicProfileApi;

  /// 拉取公开主页；未登录也能看（带 token 则返回关注状态）
  static Future<Map<String, dynamic>?> fetchProfile(int uid) async {
    final token = AuthService.getLocalToken();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('$api?uid=$uid'));
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('User-Agent', 'yhdm-mobile/1.0');
      final resp = await req.close();
      final s = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(s) as Map<String, dynamic>;
      if (j['profile'] is Map) {
        return Map<String, dynamic>.from(j['profile'] as Map);
      }
      return null;
    } catch (e) {
      client.close();
      KazumiLogger().e('Friend: 拉取主页失败', error: e);
      return null;
    }
  }

  /// 关注 / 取关 / 查询状态
  static Future<Map<String, dynamic>> follow(int uid) => _post('follow', uid);
  static Future<Map<String, dynamic>> unfollow(int uid) => _post('unfollow', uid);
  static Future<Map<String, dynamic>> status(int uid) => _post('status', uid);

  static Future<Map<String, dynamic>> _post(String action, int uid) async {
    final token = AuthService.getLocalToken();
    if (token == null) return {'error': '未登录'};
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final body = <String, dynamic>{'action': action, 'uid': uid};
      final req = await client.postUrl(Uri.parse('$api?action=$action'));
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('User-Agent', 'yhdm-mobile/1.0');
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close();
      final s = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode != 200) {
        try {
          final j = jsonDecode(s);
          if (j is Map && j['error'] != null) {
            return {'error': j['error'].toString()};
          }
        } catch (_) {}
        return {'error': '请求失败（HTTP ${resp.statusCode}）'};
      }
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (e) {
      client.close();
      KazumiLogger().e('Friend: 请求失败', error: e);
      return {'error': '网络连接失败: $e'};
    }
  }
}

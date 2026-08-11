import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 管理员服务（对接后端 danmaku_admin.php?api=1）
///
/// 管理员在 App 内即可：
/// - 查询自己的管理员身份 + 头衔（[me]）
/// - 修改自己的头衔（[setTitle]）
/// - 置顶/取消置顶自己发布的评论（[pinSelf]）
class AdminService {
  AdminService._();

  static const String baseUrl = 'https://qlyyz.xyz/api/danmaku_admin.php';

  /// 当前用户管理员状态缓存
  static ({bool admin, String headTitle})? _cache;

  static ({bool admin, String headTitle})? get cached => _cache;

  static Future<Map<String, dynamic>> _post(
    String action,
    Map<String, dynamic> body,
  ) async {
    final token = AuthService.getLocalToken();
    if (token == null) {
      return {'success': false, 'error': '未登录'};
    }
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request =
          await client.postUrl(Uri.parse('$baseUrl?api=1&action=$action'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $token');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final resp = await response.transform(utf8.decoder).join();
      client.close();
      return jsonDecode(resp) as Map<String, dynamic>;
    } catch (e) {
      KazumiLogger().e('Admin: 请求失败 action=$action', error: e);
      return {'success': false, 'error': '网络异常'};
    }
  }

  /// 查询当前用户是否管理员 + 头衔
  static Future<({bool admin, String headTitle})?> me(
      {bool refresh = false}) async {
    if (!refresh && _cache != null) return _cache;
    final res = await _post('me', {});
    if (res['success'] != true) return null;
    _cache = (
      admin: res['admin'] == true,
      headTitle: res['head_title']?.toString() ?? '',
    );
    return _cache;
  }

  /// 管理员：修改自己的头衔（≤20 字）
  static Future<String?> setTitle(String title) async {
    final res = await _post('set_title', {'title': title});
    if (res['success'] != true) {
      return res['error']?.toString() ?? '设置失败';
    }
    _cache = (
      admin: true,
      headTitle: res['head_title']?.toString() ?? title,
    );
    return null;
  }

  /// 管理员：置顶/取消置顶自己发布的评论
  static Future<String?> pinSelf(int commentId, {required bool pinned}) async {
    final res = await _post('pin_self', {
      'commentId': commentId,
      'pinned': pinned,
    });
    if (res['success'] != true) {
      return res['error']?.toString() ?? '操作失败';
    }
    return null;
  }
}

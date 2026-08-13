// lib/services/admin_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';

class AdminService {
  AdminService._();

  static const String baseUrl = 'https://qlyyz.xyz/api/danmaku_admin.php';

  static ({bool admin, String headTitle, String uid})? _cache;
  static List<MutedUser>? _muteListCache;

  static ({bool admin, String headTitle, String uid})? get cached => _cache;

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
  static Future<({bool admin, String headTitle, String uid})?> me({
    bool refresh = false,
  }) async {
    if (!refresh && _cache != null) return _cache;
    final res = await _post('me', {});
    KazumiLogger().i('Admin me response: $res');
    if (res['success'] != true) return null;
    _cache = (
      admin: res['admin'] == true,
      headTitle: res['head_title']?.toString() ?? '',
      uid: res['uid']?.toString() ?? '',
    );
    return _cache;
  }

  /// 检查当前用户是否为管理员
  static Future<bool> isAdmin() async {
    try {
      final info = await me(refresh: true);
      return info?.admin ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 获取当前用户 uid
  static Future<String?> getUid() async {
    final info = await me();
    return info?.uid;
  }

  /// 修改头衔
  static Future<String?> setTitle(String title) async {
    if (title.isEmpty || title.length > 20) {
      return '头衔1-20个字';
    }
    final res = await _post('set_title', {'title': title});
    if (res['success'] != true) {
      return res['error']?.toString() ?? '设置失败';
    }
    if (_cache != null) {
      _cache = (
        admin: _cache!.admin,
        headTitle: res['head_title']?.toString() ?? title,
        uid: _cache!.uid,
      );
    }
    return null;
  }

  /// 置顶/取消置顶自己发布的评论
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

  /// 禁言用户
  static Future<String?> muteUser({
    required int uid,
    required int duration,
    String? reason,
  }) async {
    final res = await _post('mute_user', {
      'uid': uid.toString(),
      'duration': duration,
      'reason': reason ?? '',
    });
    if (res['success'] != true) {
      return res['error']?.toString() ?? '禁言失败';
    }
    _muteListCache = null;
    return null;
  }

  /// 解禁用户
  static Future<String?> unmuteUser(int uid) async {
    final res = await _post('unmute_user', {'uid': uid.toString()});
    if (res['success'] != true) {
      return res['error']?.toString() ?? '解禁失败';
    }
    _muteListCache = null;
    return null;
  }

  /// 获取禁言列表
  static Future<List<MutedUser>> getMuteList({bool refresh = false}) async {
    if (!refresh && _muteListCache != null) {
      return _muteListCache!;
    }
    final res = await _post('mute_list', {});
    if (res['success'] != true) {
      return [];
    }
    final list = (res['list'] as List?) ?? [];
    _muteListCache = list.map((item) {
      return MutedUser(
        uid: int.tryParse(item['uid']?.toString() ?? '0') ?? 0,
        nickname: item['nickname']?.toString() ?? '用户',
        avatar: item['avatar']?.toString() ?? '',
        mutedAt: DateTime.tryParse(item['muted_at']?.toString() ?? '') ?? DateTime.now(),
        expireAt: item['expire_at'] != null
            ? DateTime.tryParse(item['expire_at'].toString())
            : null,
        reason: item['reason']?.toString() ?? '',
        isPermanent: item['is_permanent'] == true,
        isExpired: item['is_expired'] == true,
      );
    }).toList();
    return _muteListCache!;
  }

  /// 检查用户是否被禁言
  static Future<bool> isUserMuted(int uid) async {
    try {
      final list = await getMuteList();
      return list.any((user) => user.uid == uid && !user.isExpired);
    } catch (_) {
      return false;
    }
  }

  /// 清除缓存
  static void clearCache() {
    _cache = null;
    _muteListCache = null;
  }
}

/// 被禁言用户信息
class MutedUser {
  final int uid;
  final String nickname;
  final String avatar;
  final DateTime mutedAt;
  final DateTime? expireAt;
  final String reason;
  final bool isPermanent;
  final bool isExpired;

  MutedUser({
    required this.uid,
    required this.nickname,
    required this.avatar,
    required this.mutedAt,
    this.expireAt,
    required this.reason,
    required this.isPermanent,
    this.isExpired = false,
  });

  String get remainingTime {
    if (isPermanent) return '永久';
    if (expireAt == null) return '未知';
    if (isExpired) return '已过期';
    final diff = expireAt!.difference(DateTime.now());
    if (diff.inDays > 0) return '${diff.inDays}天';
    if (diff.inHours > 0) return '${diff.inHours}小时';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟';
    return '${diff.inSeconds}秒';
  }
}
import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 社交用户资料
class SocialProfile {
  const SocialProfile({
    required this.uid,
    required this.nickname,
    required this.avatar,
    this.createdAt = 0,
  });

  final String uid;
  final String nickname;
  final String avatar;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'nickname': nickname,
        'avatar': avatar,
        'created_at': createdAt,
      };

  factory SocialProfile.fromJson(Map<String, dynamic> json) => SocialProfile(
        uid: json['uid']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? '',
        avatar: json['avatar']?.toString() ?? '',
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// 聊天消息
class SocialChatMessage {
  const SocialChatMessage({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.type,
    required this.content,
    required this.createdAt,
  });

  final int id;
  final String fromUid;
  final String toUid;
  final String type; // text / emoji / anime / rule
  final String content;
  final int createdAt;

  factory SocialChatMessage.fromJson(Map<String, dynamic> json) =>
      SocialChatMessage(
        id: (json['id'] as num?)?.toInt() ?? 0,
        fromUid: json['from_uid']?.toString() ?? '',
        toUid: json['to_uid']?.toString() ?? '',
        type: json['type']?.toString() ?? 'text',
        content: json['content']?.toString() ?? '',
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// 社交接口（后端 qlyyz.xyz/api/log/log.php）
///
/// 认证使用 login.php 的 Bearer token；新增接口统一走 api/log/ 目录。
class SocialService {
  SocialService._();

  static const String baseUrl = 'https://qlyyz.xyz/api/log/log.php';

  /// 当前登录用户的本地资料缓存
  static SocialProfile? _myProfile;

  static SocialProfile? get myProfile => _myProfile;

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
          await client.postUrl(Uri.parse('$baseUrl?action=$action'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $token');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final resp = await response.transform(utf8.decoder).join();
      client.close();
      return jsonDecode(resp) as Map<String, dynamic>;
    } catch (e) {
      KazumiLogger().e('Social: 请求失败 action=$action', error: e);
      return {'success': false, 'error': '网络异常'};
    }
  }

  static bool _isSuccess(Map<String, dynamic> res) => res['success'] == true;

  /// 头像代理：服务器在美国丢包率高，统一走 wsrv.nl 图片代理
  /// （与评论头像同一代理，保证加载稳定）
  static String proxiedAvatar(String avatar) {
    const proxyBase = 'https://wsrv.nl/?url=';
    final url = avatar.isNotEmpty ? avatar : 'https://qlyyz.xyz/logo.webp';
    return '$proxyBase${Uri.encodeComponent(url)}';
  }

  /// 获取当前用户资料（后端自动建号分配 uid/默认昵称/默认头像）
  static Future<SocialProfile?> getProfile({bool refresh = false}) async {
    if (!refresh && _myProfile != null) return _myProfile;
    final res = await _post('profile_get', {});
    if (!_isSuccess(res)) return null;
    final p = res['profile'];
    if (p is! Map) return null;
    _myProfile = SocialProfile.fromJson(Map<String, dynamic>.from(p));
    // 缓存到本地
    await GStorage.putSetting(
        SettingsKeys.socialProfile, jsonEncode(_myProfile!.toJson()));
    return _myProfile;
  }

  /// 从本地缓存恢复资料（登录后/启动时调用，失败再拉远程）
  static SocialProfile? restoreLocalProfile() {
    if (_myProfile != null) return _myProfile;
    final raw = GStorage.getSetting(SettingsKeys.socialProfile);
    if (raw.isEmpty) return null;
    try {
      _myProfile = SocialProfile.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
      return _myProfile;
    } catch (_) {
      return null;
    }
  }

  /// 修改昵称/头像
  static Future<String?> updateProfile({
    String? nickname,
    String? avatar,
  }) async {
    final res = await _post('profile_update', {
      if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
      if (avatar != null && avatar.isNotEmpty) 'avatar': avatar,
    });
    if (!_isSuccess(res)) return res['error']?.toString() ?? '更新失败';
    // 更新缓存
    _myProfile = null;
    await getProfile(refresh: true);
    return null;
  }

  /// 上传头像（base64），返回头像 URL
  static Future<String?> uploadAvatar(String base64Image) async {
    final res = await _post('avatar_upload', {'data': base64Image});
    if (!_isSuccess(res)) return res['error']?.toString() ?? '上传失败';
    final url = res['avatar']?.toString() ?? '';
    if (url.isNotEmpty) {
      await updateProfile(avatar: url);
      return null;
    }
    return '上传失败';
  }

  /// 搜索用户（按 uid / 昵称）
  static Future<List<SocialProfile>> searchUsers(String keyword) async {
    final res = await _post('profile_search', {'keyword': keyword});
    if (!_isSuccess(res)) return [];
    final list = res['users'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => SocialProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 发送好友申请
  static Future<String?> addFriend(String uid) async {
    final res = await _post('friend_add', {'uid': uid});
    if (_isSuccess(res)) return null;
    return res['error']?.toString() ?? '添加失败';
  }

  /// 收到的申请列表
  static Future<List<SocialProfile>> friendRequests() async {
    final res = await _post('friend_requests', {});
    if (!_isSuccess(res)) return [];
    final list = res['requests'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => SocialProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 同意 / 拒绝申请
  static Future<String?> handleFriendRequest(String uid,
      {required bool accept}) async {
    final res = await _post(accept ? 'friend_accept' : 'friend_reject', {
      'uid': uid,
    });
    if (_isSuccess(res)) return null;
    return res['error']?.toString() ?? '操作失败';
  }

  /// 好友列表
  static Future<List<SocialProfile>> friendList() async {
    final res = await _post('friend_list', {});
    if (!_isSuccess(res)) return [];
    final list = res['friends'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => SocialProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 删除好友
  static Future<String?> removeFriend(String uid) async {
    final res = await _post('friend_remove', {'uid': uid});
    if (_isSuccess(res)) return null;
    return res['error']?.toString() ?? '删除失败';
  }

  /// 发送消息（type: text / emoji / anime / rule）
  static Future<String?> sendMessage({
    required String toUid,
    required String type,
    required String content,
  }) async {
    final res = await _post('chat_send', {
      'to_uid': toUid,
      'type': type,
      'content': content,
    });
    if (_isSuccess(res)) return null;
    return res['error']?.toString() ?? '发送失败';
  }

  /// 与某用户的聊天记录（最新在前）
  static Future<List<SocialChatMessage>> chatHistory(String uid) async {
    final res = await _post('chat_history', {'uid': uid, 'limit': 100});
    if (!_isSuccess(res)) return [];
    final list = res['messages'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => SocialChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 发起账号销毁（7 天冷静期）
  static Future<String?> requestDeleteAccount() async {
    final res = await _post('delete_account', {'confirm': true});
    if (_isSuccess(res)) return null;
    return res['error']?.toString() ?? '操作失败';
  }

  /// 取消销毁（登录后自动调用）
  static Future<void> cancelDelete() async {
    await _post('cancel_delete', {});
  }

  /// 查询销毁状态
  static Future<({bool pending, int deleteAt, int remainingDays})?>
      deleteStatus() async {
    final res = await _post('delete_status', {});
    if (!_isSuccess(res)) return null;
    return (
      pending: res['pending'] == true,
      deleteAt: (res['delete_at'] as num?)?.toInt() ?? 0,
      remainingDays: (res['remaining_days'] as num?)?.toInt() ?? 0,
    );
  }

  /// 登录成功后初始化：拉资料 + 取消销毁（若有）
  static Future<void> ensureProfileAfterLogin() async {
    restoreLocalProfile();
    await getProfile(refresh: true);
    final status = await deleteStatus();
    if (status?.pending == true) {
      await cancelDelete();
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/notification/anime_update_notification_service.dart';
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
class SocialChatMessage {  const SocialChatMessage({
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

/// 最近会话（会话列表用）
class SocialConversation {
  const SocialConversation({
    required this.uid,
    required this.nickname,
    required this.avatar,
    required this.lastId,
    required this.lastType,
    required this.lastContent,
    required this.lastTime,
  });

  final String uid;
  final String nickname;
  final String avatar;
  final int lastId;
  final String lastType;
  final String lastContent;
  final int lastTime;

  factory SocialConversation.fromJson(Map<String, dynamic> json) =>
      SocialConversation(
        uid: json['uid']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? '',
        avatar: json['avatar']?.toString() ?? '',
        lastId: (json['last_id'] as num?)?.toInt() ?? 0,
        lastType: json['last_type']?.toString() ?? 'text',
        lastContent: json['last_content']?.toString() ?? '',
        lastTime: (json['last_time'] as num?)?.toInt() ?? 0,
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

  /// 头像地址：用户头像在自有服务器上，直连加载即可。
  /// 不再走 wsrv.nl 代理（自有服务器只是慢，代理反而超时）；
  /// 仅 Bangumi 评论头像因图床被墙继续走代理（见 info_controller）。
  static String proxiedAvatar(String avatar) {
    return avatar.isNotEmpty ? avatar : 'https://qlyyz.xyz/logo.webp';
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
  static Future<List<SocialChatMessage>> chatHistory(String uid,
      {int limit = 100}) async {
    final res =
        await _post('chat_history', {'uid': uid, 'limit': limit});
    if (!_isSuccess(res)) return [];
    final list = res['messages'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => SocialChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 🆕 最近会话列表（好友 + 最后一条消息，按最后消息时间倒序）
  ///
  /// 由本地好友列表 + 各好友最新消息构造（后端不额外存会话表）。
  static Future<List<SocialConversation>> chatRecent() async {
    final friends = await friendList();
    final result = <SocialConversation>[];
    for (final f in friends) {
      try {
        final msgs = await chatHistory(f.uid, limit: 5);
        if (msgs.isEmpty) {
          result.add(SocialConversation(
            uid: f.uid,
            nickname: f.nickname,
            avatar: f.avatar,
            lastId: 0,
            lastType: 'text',
            lastContent: '',
            lastTime: 0,
          ));
          continue;
        }
        SocialChatMessage? last;
        for (final m in msgs) {
          if (last == null || m.id > last.id) last = m;
        }
        result.add(SocialConversation(
          uid: f.uid,
          nickname: f.nickname,
          avatar: f.avatar,
          lastId: last!.id,
          lastType: last.type,
          lastContent: last.content,
          lastTime: last.createdAt,
        ));
      } catch (_) {
        // 单个好友失败跳过
      }
    }
    result.sort((a, b) => b.lastTime.compareTo(a.lastTime));
    return result;
  }

  /// 未读管理：本地记录每好友最后已读的消息 id
  static Map<String, int>? _lastReadCache;

  static Map<String, int> _loadLastRead() {
    if (_lastReadCache != null) return _lastReadCache!;
    try {
      final raw = GStorage.getSetting(SettingsKeys.chatLastRead);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      _lastReadCache = decoded.map((k, v) =>
          MapEntry(k.toString(), (v as num).toInt()));
      return _lastReadCache!;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveLastRead() async {
    await GStorage.putSetting(
        SettingsKeys.chatLastRead, jsonEncode(_lastReadCache ?? {}));
  }

  /// 某好友未读消息数（lastId > 已读id 且消息是对方发的）
  static int unreadOf(SocialConversation conv) {
    final read = _loadLastRead()[conv.uid] ?? 0;
    if (conv.lastId <= read) return 0;
    return conv.lastType == 'text' ? 1 : 1; // 会话级未读，简单计 1
  }

  /// 是否已读（lastId <= 已读id）
  static bool isRead(String uid, int lastId) {
    final read = _loadLastRead()[uid] ?? 0;
    return lastId <= read;
  }

  /// 标记某好友已读
  static Future<void> markRead(String uid, int lastId) async {
    _loadLastRead();
    final current = _lastReadCache![uid] ?? 0;
    if (lastId > current) {
      _lastReadCache![uid] = lastId;
      await _saveLastRead();
    }
  }

  /// 所有未读总数（会话级）
  static Future<int> totalUnread() async {
    final convs = await chatRecent();
    return convs.where((c) => unreadOf(c) > 0).length;
  }

  /// 🆕 轮询好友新消息并推送系统通知（由"消息"会话页定时调用）
  ///
  /// 已通知过的消息 id 记录在内存，避免重复推送；
  /// 用户打开聊天后 [markRead] 清零未读。
  static final Set<int> _notifiedMessageIds = {};

  static Future<void> pollNewMessages() async {
    final convs = await chatRecent();
    for (final c in convs) {
      if (c.lastId <= 0 || _notifiedMessageIds.contains(c.lastId)) continue;
      if (unreadOf(c) <= 0) continue;
      _notifiedMessageIds.add(c.lastId);
      // 防止集合无限增长
      if (_notifiedMessageIds.length > 200) {
        _notifiedMessageIds.clear();
      }
      await AnimeUpdateNotificationService.showNotification(
        title: c.nickname,
        body: _messagePreview(c.lastType, c.lastContent),
        payload: 'chat:${c.uid}',
      );
    }
  }

  /// 消息预览（表情/动漫/规则特殊显示）
  static String _messagePreview(String type, String content) {
    switch (type) {
      case 'emoji':
        return content;
      case 'anime':
        return '[分享的番剧] $content';
      case 'rule':
        return '[分享的规则] $content';
      default:
        return content;
    }
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

import 'dart:convert';
import 'dart:io';

import 'package:yhdm/services/auth_service.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/notification/anime_update_notification_service.dart';
import 'package:yhdm/services/storage/settings_keys.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/utils/api_throttle.dart';

/// 社交用户资料
class SocialProfile {
  const SocialProfile({
    required this.uid,
    required this.nickname,
    required this.avatar,
    this.createdAt = 0,
    this.lastSeen = 0,
    this.hideOnline = false,
    this.bio = '',
    this.gender = 0,
    this.birthday = '',
    this.privacy = false,
    this.isOnline = false,
    this.allowViewProfile = true,
    this.allowViewInfo = true,
    this.allowAddFriend = true,
  });

  final String uid;
  final String nickname;
  final String avatar;
  final int createdAt;

  /// 🆕 最后活跃时间戳（秒）；0 = 未公开/离线
  final int lastSeen;

  /// 🆕 是否隐藏在线状态（好友看不到我的在线）
  final bool hideOnline;

  /// 🆕 个人介绍（最多 200 字）
  final String bio;

  /// 🆕 性别（0=保密 1=男 2=女 3=其他）
  final int gender;

  /// 🆕 生日（YYYY-MM-DD，空=不填）
  final String birthday;

  /// 🆕 隐私用户（对方不允许查看主页 → 主页只显示遮挡信息）
  final bool privacy;

  /// 🆕 是否在线（查看他人主页时由后端返回）
  final bool isOnline;

  /// 🆕 隐私设置：允许他人查看主页
  final bool allowViewProfile;

  /// 🆕 隐私设置：允许他人查看资料（介绍/性别/生日）
  final bool allowViewInfo;

  /// 🆕 隐私设置：允许他人添加好友
  final bool allowAddFriend;

  /// 🆕 是否在线（最近 5 分钟内有活跃且公开）
  bool get isOnlineNow {
    if (privacy) return false;
    if (hideOnline) return false;
    if (lastSeen <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 - lastSeen < 300;
  }

  String get genderText {
    switch (gender) {
      case 1: return '男';
      case 2: return '女';
      case 3: return '其他';
      default: return '保密';
    }
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'nickname': nickname,
        'avatar': avatar,
        'created_at': createdAt,
        'last_seen': lastSeen,
        'bio': bio,
        'gender': gender,
        'birthday': birthday,
        'allow_view_profile': allowViewProfile ? 1 : 0,
        'allow_view_info': allowViewInfo ? 1 : 0,
        'allow_add_friend': allowAddFriend ? 1 : 0,
      };

  factory SocialProfile.fromJson(Map<String, dynamic> json) => SocialProfile(
        uid: json['uid']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? '',
        avatar: json['avatar']?.toString() ?? '',
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
        lastSeen: (json['last_seen'] as num?)?.toInt() ?? 0,
        hideOnline: (json['hide_online'] as num?)?.toInt() == 1,
        bio: json['bio']?.toString() ?? '',
        gender: (json['gender'] as num?)?.toInt() ?? 0,
        birthday: json['birthday']?.toString() ?? '',
        privacy: json['privacy'] == true,
        isOnline: json['is_online'] == true,
        allowViewProfile: (json['allow_view_profile'] as num?)?.toInt() != 0,
        allowViewInfo: (json['allow_view_info'] as num?)?.toInt() != 0,
        allowAddFriend: (json['allow_add_friend'] as num?)?.toInt() != 0,
      );
}

/// 社交接口（后端 qlyyz.xyz/api/log/log.php）
///
/// 认证使用 login.php 的 Bearer token；新增接口统一走 api/log/ 目录。
class SocialService {
  SocialService._();

  static const String baseUrl = 'https://qlyyz.xyz/api/v1/log/log.php';

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
    String resp = '';
    int statusCode = 0;
    try {
      await ApiThrottle.wait(); // 🆕 全局限流，避免 Kangle 防 CC 触发 JS 验证页
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      // 🆕 浏览器 UA + 完整头：Kangle WAF 对非浏览器(dart:io 默认UA)返回 JS 验证页(cbk_var)导致解析失败
      client.userAgent =
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
      final request =
          await client.postUrl(Uri.parse('$baseUrl?action=$action'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json, text/plain, */*');
      request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');
      request.headers.set('Referer', 'https://qlyyz.xyz/');
      request.headers.set('Authorization', 'Bearer $token');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      statusCode = response.statusCode;
      resp = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode != 200) {
        // ⭐ 登录失效自动登出（社交接口同样会返回「登录已过期/未登录」）
        try {
          final errData = jsonDecode(resp) as Map<String, dynamic>;
          final err = errData['error'] ?? 'HTTP ${response.statusCode}';
          if (AuthService.isAuthFailure(err,
              statusCode: response.statusCode)) {
            AuthService.handleAuthFailure();
            return {...errData, 'auth_failed': true};
          }
          return errData;
        } catch (_) {
          if (response.statusCode == 401 || response.statusCode == 403) {
            AuthService.handleAuthFailure();
          }
          return {'success': false, 'error': 'HTTP ${response.statusCode}'};
        }
      }
      return jsonDecode(resp) as Map<String, dynamic>;
    } catch (e) {
      // 🆕 记录状态码 + 响应原文，便于判断是 Kangle 验证页 / 空响应 / 正常 JSON
      final preview = resp.length > 800 ? resp.substring(0, 800) : resp;
      KazumiLogger().e(
          'Social: 请求失败 action=$action status=$statusCode',
          error: e,
          forceLog: true);
      KazumiLogger().w('Social: 响应原文: $preview', forceLog: true);
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
    // 🆕 UID 已在 Hive 持久化（socialProfile key），且 uid 为 final 不可修改。
    // 参考追番页"本地优先 + 变化才写盘"：仅当资料（头像/昵称等）真正变化时才覆盖写，
    // 避免每次拉取 profile 都重复写盘。
    final json = jsonEncode(_myProfile!.toJson());
    if (GStorage.getSetting(SettingsKeys.socialProfile) != json) {
      await GStorage.putSetting(SettingsKeys.socialProfile, json);
    }
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

  /// 修改昵称/头像/隐藏在线状态/个人介绍/性别/生日
  static Future<String?> updateProfile({
    String? nickname,
    String? avatar,
    bool? hideOnline,
    String? bio,
    int? gender,
    String? birthday,
  }) async {
    final res = await _post('profile_update', {
      if (nickname != null) 'nickname': nickname, // 允许空字符串（清空昵称？但实际昵称不能为空，后端会处理）
      if (avatar != null && avatar.isNotEmpty) 'avatar': avatar,
      if (hideOnline != null) 'hide_online': hideOnline,
      if (bio != null) 'bio': bio, // 🆕 允许空字符串，用户可清空个人介绍
      if (gender != null) 'gender': gender,
      if (birthday != null) 'birthday': birthday, // 🆕 允许空字符串，用户可清空生日
    });
    if (!_isSuccess(res)) return res['error']?.toString() ?? '更新失败';
    // 更新缓存
    _myProfile = null;
    await getProfile(refresh: true);
    return null;
  }

  /// 🆕 保存隐私设置（1=允许 0=禁止；默认全禁止保护隐私）
  /// [allowViewProfile] 允许他人查看主页
  /// [allowViewInfo] 允许他人查看资料（介绍/性别/生日）
  /// [allowAddFriend] 允许他人添加好友
  static Future<String?> updatePrivacy({
    bool? allowViewProfile,
    bool? allowViewInfo,
    bool? allowAddFriend,
  }) async {
    final res = await _post('privacy_update', {
      if (allowViewProfile != null) 'allow_view_profile': allowViewProfile,
      if (allowViewInfo != null) 'allow_view_info': allowViewInfo,
      if (allowAddFriend != null) 'allow_add_friend': allowAddFriend,
    });
    if (_isSuccess(res)) return null;
    return res['error']?.toString() ?? '保存失败';
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

  /// 🆕 我的星标规则（从服务器拉取；失败时用本地缓存）
  static List<String>? _starCache;

  static Future<List<String>> getStarRules() async {
    if (_starCache != null) return _starCache!;
    final res = await _post('rules_star_get', {});
    if (_isSuccess(res)) {
      final list = res['rules'];
      if (list is List) {
        _starCache = list.map((e) => e.toString()).toList();
        return _starCache!;
      }
    }
    // 网络失败用本地缓存
    final local = GStorage.getStringListSettingByName('starRules');
    if (local.isNotEmpty) {
      _starCache = local;
      return _starCache!;
    }
    return [];
  }

  /// 🆕 保存星标规则到服务器 + 本地
  static Future<String?> saveStarRules(List<String> rules) async {
    final res = await _post('rules_star_save', {'rules': rules});
    if (!_isSuccess(res)) return res['error']?.toString() ?? '保存失败';
    _starCache = List.from(rules);
    await GStorage.putStringListSettingByName('starRules', rules);
    return null;
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

  /// 🆕 清除本地资料缓存（退出登录 / 切换账号时必须调用，避免残留上一账号头像/uid）
  static void clearProfileCache() {
    _myProfile = null;
    try {
      GStorage.putSetting(SettingsKeys.socialProfile, '');
    } catch (_) {}
  }

  /// 登录成功后初始化：清除旧缓存 → 拉取新账号资料 → 取消账号销毁（若有）
  static Future<void> ensureProfileAfterLogin() async {
    // 🔧 先清空旧账号缓存，确保扫码/切换账号后头像、uid 正确刷新
    clearProfileCache();
    await getProfile(refresh: true);
    final status = await deleteStatus();
    if (status?.pending == true) {
      await cancelDelete();
    }
  }
}

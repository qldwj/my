import 'dart:convert';
import 'dart:io';

import 'package:yhdm/request/config/api_endpoints.dart';
import 'package:yhdm/services/auth_service.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/storage/settings_keys.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/utils/api_throttle.dart';

/// 在线状态 / 心跳上报客户端
///
/// 对接后端 v1/presence.php（Bearer token 鉴权，MySQL users 表）：
/// - beat    ：定时心跳，status=playing/online，可携带当前播放的番剧/剧集
/// - online  ：退出播放页专用，把状态从 playing 降回 online（清 subject）
/// - me      ：只查询登录态，成功返回 {user:{...}}，失败返回 {auth_failed:true}
///
/// 状态语义：
///   playing   → 正在播放页且有 subject_id
///   online    → App 活跃但不播放
///   offline   → last_seen 超过 180s，服务端懒判定
class PresenceService {
  PresenceService._();

  static const String api = ApiEndpoints.presenceApi;

  /// 当前登录用户信息（最近一次 whoAmI / beat 成功时服务端回传，
  /// 供 App 各处读取以展示头像/昵称/UID）。登出时置 null。
  static Map<String, dynamic>? _currentUser;
  static void Function()? onUserChanged;
  static Map<String, dynamic>? get currentUser => _currentUser;

  static void clearCurrentUser() {
    if (_currentUser == null) return;
    _currentUser = null;
    try { onUserChanged?.call(); } catch (_) {}
  }

  /// 把服务端返回的 user 字段写入缓存；与当前缓存不一致才通知变更
  static void _applyUser(Map<String, dynamic> resp) {
    final u = PresenceService.extractUser(resp);
    if (u == null) return;
    if (_currentUser == null || _currentUser.toString() != u.toString()) {
      _currentUser = u;
      try { onUserChanged?.call(); } catch (_) {}
    }
  }

  /// 当前 App 版本（读 pubspec 里那份）
  static const String _appVersion = '2.4.3';

  /// 用户是否允许上报在线状态（「我的」页右上角眼睛按钮控制）
  static bool get enabled =>
      GStorage.getSetting(SettingsKeys.presenceVisibilityEnabled);

  static Map<String, dynamic> _deviceInfo() {
    return {
      'device_name': AuthService.currentDeviceName(),
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'app_version': _appVersion,
    };
  }

  static Future<Map<String, dynamic>> _post(
    String action,
    Map<String, dynamic> body, {
    bool requireLogin = true,
  }) async {
    final token = AuthService.getLocalToken();
    if (token == null) {
      return requireLogin ? {'error': '未登录'} : {'auth_failed': true};
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    String s = '';
    int statusCode = 0;
    try {
      await ApiThrottle.wait();
      final req = await client.postUrl(Uri.parse('$api?action=$action'));
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');
      req.headers.set('Accept', 'application/json, text/plain, */*');
      req.headers.set('Referer', 'https://qlyyz.xyz/');
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close();
      statusCode = resp.statusCode;
      s = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode != 200) {
        final err = 'HTTP ${resp.statusCode}';
        if (statusCode == 401 || statusCode == 403) {
          AuthService.handleAuthFailure();
          return {'error': err, 'auth_failed': true};
        }
        return {'error': err};
      }
      final data = jsonDecode(s);
      if (data is! Map) return {'error': '响应格式异常'};
      final map = Map<String, dynamic>.from(data);
      // 服务端每次响应都带 user 字段，顺手缓存（登出时另行清）
      if (map['success'] == true) _applyUser(map);
      return map;
    } catch (e) {
      client.close();
      KazumiLogger().w('Presence: $action failed status=$statusCode',
          forceLog: true);
      return {'error': '网络错误: $e'};
    }
  }

  /// 上报「正在播放」——播放页 initState / 播放 tick 时调用
  ///
  /// subjectId = Bangumi 番剧 ID；episodeId = Bangumi episode ID（可 0）
  /// progress / duration 单位：秒
  static Future<Map<String, dynamic>> beatPlaying({
    required int subjectId,
    int episodeId = 0,
    int episodeNo = 0,
    int progress = 0,
    int duration = 0,
  }) {
    if (!enabled) return Future.value({});
    return _post('beat', {
      'status': 'playing',
      'subject_id': subjectId,
      'episode_id': episodeId,
      'episode_no': episodeNo,
      'progress': progress,
      'duration': duration,
      ..._deviceInfo(),
    });
  }

  /// 上报「在线，未在播放」——播放页 dispose / App 启动时调用
  static Future<Map<String, dynamic>> beatOnline() {
    if (!enabled) return Future.value({});
    return _post('online', {
      'status': 'online',
      ..._deviceInfo(),
    });
  }

  /// 退出播放页专用：把状态从 playing 降为 online 并清空 subject
  ///
  /// 复用 online 端点（服务端强制 status=online 且清 subject）
  static Future<Map<String, dynamic>> reportStopped() {
    if (!enabled) return Future.value({});
    return _post('online', {
      'status': 'online',
      ..._deviceInfo(),
    });
  }

  /// 只查询当前登录态
  ///
  /// 成功：{success:true, status:..., user:{uid,email,nickname,avatar,created_at}}
  /// 未登录/token 无效：{success:false, auth_failed:true, error:'未登录'}
  ///
  /// [requireLogin] 默认 true，需要登录；传 false 时未登录也返回 auth_failed
  /// 而不是本地短路。
  static Future<Map<String, dynamic>> whoAmI() {
    return _post('me', {}, requireLogin: false);
  }

  /// 全局在线状态汇总（公开接口，不需登录）
  ///
  /// 返回：
  /// {
  ///   success: true,
  ///   summary: { online, playing, offline },
  ///   devices: { 'Android': 8, 'iOS': 3, ... },
  ///   apps:    { '2.4.3': 10, ... },
  ///   playing: [ { uid, email, nickname, avatar, status, subject:{...}, device:{...}, seconds_ago }, ... ],
  ///   online:  [ ... ],
  ///   offline_after_seconds: 180,
  ///   snapshot_at: 1234567890
  /// }
  ///
  /// 公开接口不走 Bearer token，直接用无认证的 POST
  static Future<Map<String, dynamic>> stats() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    String s = '';
    try {
      await ApiThrottle.wait();
      final req = await client.postUrl(Uri.parse('$api?action=stats'));
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');
      req.headers.set('Referer', 'https://qlyyz.xyz/');
      req.add(utf8.encode('{}'));
      final resp = await req.close();
      s = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode != 200) return {'error': 'HTTP ${resp.statusCode}'};
      final data = jsonDecode(s);
      return data is Map ? Map<String, dynamic>.from(data) : {'error': '响应异常'};
    } catch (e) {
      client.close();
      return {'error': '网络错误: $e'};
    }
  }

  /// 从 whoAmI / beat 响应里解析 user 字段
  static Map<String, dynamic>? extractUser(Map<String, dynamic> resp) {
    final u = resp['user'];
    if (u is Map) return Map<String, dynamic>.from(u);
    return null;
  }

  /// 服务端返回的 status（'playing'/'online'/'offline'），未知返回 null
  static String? extractStatus(Map<String, dynamic> resp) {
    final s = resp['status'];
    return s is String && s.isNotEmpty ? s : null;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/api_throttle.dart';

/// 🆕 追番打卡 / 连看天数客户端
///
/// 对接后端 v1/checkin.php（Bearer token 鉴权，MySQL 主库）：
/// - checkin ：今日打卡（+5 积分），返回连看天数
/// - stats   ：连看天数 / 总天数 / 近 60 天打卡日历 / 积分
/// - share   ：生成打卡分享文案
class CheckinService {
  CheckinService._();

  static const String api = ApiEndpoints.checkinApi;

  static Future<Map<String, dynamic>> _post(
      String action, Map<String, dynamic>? extra) async {
    final token = AuthService.getLocalToken();
    if (token == null) return {'error': '未登录'};
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    String s = '';
    int statusCode = 0;
    try {
      await ApiThrottle.wait(); // 🆕 全局限流，避免 Kangle 防 CC 触发 JS 验证页
      final body = <String, dynamic>{'action': action, ...?extra};
      final req = await client.postUrl(Uri.parse('$api?action=$action'));
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.set('Authorization', 'Bearer $token');
      // 🆕 浏览器 UA + 完整头：Kangle WAF 把 yhdm-mobile 识别为机器人 → 返回 JS 验证页(cbk_var)导致解析失败
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');
      req.headers.set('Accept', 'application/json, text/plain, */*');
      req.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');
      req.headers.set('Referer', 'https://qlyyz.xyz/');
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close();
      statusCode = resp.statusCode;
      s = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode != 200) return {'error': 'HTTP ${resp.statusCode}: $s'};
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (e) {
      client.close();
      // 🆕 记录状态码 + 响应原文，便于判断 Kangle 验证页 / 空响应 / 正常 JSON
      final preview = s.length > 800 ? s.substring(0, 800) : s;
      KazumiLogger().e('Checkin: 请求失败 status=$statusCode',
          error: e, forceLog: true);
      KazumiLogger().w('Checkin: 响应原文: $preview', forceLog: true);
      return {'error': '网络连接失败: $e'};
    }
  }

  /// 获取打卡统计（连看天数/总天数/近60天日历/积分）
  static Future<Map<String, dynamic>> stats() => _post('stats', null);

  /// 今日打卡
  static Future<Map<String, dynamic>> checkin({int bangumiId = 0}) =>
      _post('checkin', {'bangumi_id': bangumiId});

  /// 生成分享文案
  static Future<Map<String, dynamic>> share() => _post('share', null);

  /// 🆕 成就系统：追番/连签/累计/积分/绑定账号/Bangumi 解锁列表 + 当前称号
  /// [collectCount] = 本机追番收藏数（看动漫维度）
  /// 结果 Hive 持久化（变化才写盘），请求失败时退回缓存
  static const String _achCacheKey = 'checkin_achievements_cache';

  static Future<Map<String, dynamic>> achievements(
      {int collectCount = 0}) async {
    final res = await _post('achievements', {'collect_count': collectCount});
    if (res['error'] == null) {
      final newJson = jsonEncode(res);
      final cached = GStorage.getStringListSettingByName(_achCacheKey);
      if (cached.isEmpty || cached.first != newJson) {
        await GStorage.putStringListSettingByName(_achCacheKey, [newJson]);
      }
      return res;
    }
    // 请求失败：退回 Hive 缓存
    final cached = GStorage.getStringListSettingByName(_achCacheKey);
    if (cached.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(
            jsonDecode(cached.first) as Map);
      } catch (_) {}
    }
    return {'error': '请求失败'};
  }

  /// 读取 Hive 缓存的称号数据（无网络/未刷新前立即显示，
  /// 避免每次进「我的」页面称号先 0 再等网络加载）
  static Map<String, dynamic>? cachedAchievements() {
    final cached = GStorage.getStringListSettingByName(_achCacheKey);
    if (cached.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(cached.first) as Map);
      } catch (_) {}
    }
    return null;
  }

  /// 🆕 设置当前称号（从已解锁的称号中选择一个，云端保存）
  static Future<Map<String, dynamic>> setTitle(String titleName) =>
      _post('set_title', {'title': titleName});
}

import 'dart:convert';
import 'dart:io';

import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';

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
    try {
      final body = <String, dynamic>{'action': action, ...?extra};
      final req = await client.postUrl(Uri.parse('$api?action=$action'));
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('User-Agent', 'yhdm-mobile/1.0');
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close();
      final s = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode != 200) return {'error': 'HTTP ${resp.statusCode}: $s'};
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (e) {
      client.close();
      KazumiLogger().e('Checkin: 请求失败', error: e);
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
  static Future<Map<String, dynamic>> achievements({int collectCount = 0}) =>
      _post('achievements', {'collect_count': collectCount});
}

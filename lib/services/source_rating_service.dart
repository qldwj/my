import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 🆕 规则源稳定性评分客户端
///
/// 对接后端 v0/rating.php：
/// - 匿名可评，按 IP 限次防刷（每源每 IP 一条，可更新）
/// - 三维打分：stability(稳定/卡不卡) clarity(清晰度) usable(能用/可用)
/// - 聚合为总平均分，帮用户选最好用的源
class SourceRatingService {
  SourceRatingService._();

  static const String baseUrl = ApiEndpoints.sourceRatingApi;

  /// 源评分聚合数据
  static SourceRating parse(Map<String, dynamic> j) {
    return SourceRating.fromJson(j);
  }

  /// 获取某源的评分聚合（含「我」是否评过）
  static Future<SourceRating?> fetch(String sourceId) async {
    final res = await _get('get', {'sourceId': sourceId});
    if (res['success'] != true) return null;
    return SourceRating.fromJson(res);
  }

  /// 提交 / 更新评分（匿名，限IP）
  static Future<SourceRating?> submit({
    required String sourceId,
    required int stability,
    required int clarity,
    required int usable,
  }) async {
    final res = await _post('submit', {
      'sourceId': sourceId,
      'stability': stability,
      'clarity': clarity,
      'usable': usable,
    });
    if (res['success'] != true) {
      throw SourceRatingError(res['error'] ?? '提交评分失败');
    }
    return SourceRating.fromJson(res);
  }

  /// 获取评分排行（帮用户选源）
  static Future<List<SourceRating>> top({int limit = 20}) async {
    final res = await _get('top', {'limit': '$limit'});
    if (res['success'] != true) return [];
    final list = res['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => SourceRating.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ── 底层 HTTP ──

  static Future<Map<String, dynamic>> _get(String action, Map<String, String> q) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final uri = Uri.parse('$baseUrl?action=$action').replace(
          queryParameters: {...Uri.parse('$baseUrl?action=$action').queryParameters, ...q});
      final request = await client.getUrl(uri);
      final response = await request.close();
      final resp = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode != 200) return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      final j = jsonDecode(resp);
      if (j is! Map) return {'success': false, 'error': '返回格式错误'};
      return Map<String, dynamic>.from(j);
    } catch (e) {
      KazumiLogger().e('SourceRating: GET 失败 action=$action', error: e);
      return {'success': false, 'error': '网络异常'};
    }
  }

  static Future<Map<String, dynamic>> _post(String action, Map<String, dynamic> body) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request =
          await client.postUrl(Uri.parse('$baseUrl?action=$action'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final resp = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode != 200) {
        try {
          final errData = jsonDecode(resp) as Map<String, dynamic>;
          return errData;
        } catch (_) {
          return {'success': false, 'error': 'HTTP ${response.statusCode}'};
        }
      }
      final j = jsonDecode(resp);
      if (j is! Map) return {'success': false, 'error': '返回格式错误'};
      return Map<String, dynamic>.from(j);
    } catch (e) {
      KazumiLogger().e('SourceRating: POST 失败 action=$action', error: e);
      return {'success': false, 'error': '网络异常'};
    }
  }
}

/// 规则源评分聚合数据
class SourceRating {
  final String sourceId;
  final int count;
  final double total;
  final double stability;
  final double clarity;
  final double usable;
  final double usableRate;

  /// 我（本IP）的评分，null=未评过
  final MyRating? my;

  SourceRating({
    required this.sourceId,
    required this.count,
    required this.total,
    required this.stability,
    required this.clarity,
    required this.usable,
    required this.usableRate,
    this.my,
  });

  factory SourceRating.fromJson(Map<String, dynamic> j) {
    final m = j['my'];
    return SourceRating(
      sourceId: (j['sourceId'] ?? '').toString(),
      count: (j['count'] ?? 0) as int,
      total: (j['total'] ?? 0).toDouble(),
      stability: (j['stability'] ?? 0).toDouble(),
      clarity: (j['clarity'] ?? 0).toDouble(),
      usable: (j['usable'] ?? 0).toDouble(),
      usableRate: (j['usable_rate'] ?? 0).toDouble(),
      my: m is Map
          ? MyRating(
              stability: (m['stability'] ?? 0) as int,
              clarity: (m['clarity'] ?? 0) as int,
              usable: (m['usable'] ?? 0) as int,
            )
          : null,
    );
  }
}

/// 我的评分
class MyRating {
  final int stability;
  final int clarity;
  final int usable;
  MyRating({
    required this.stability,
    required this.clarity,
    required this.usable,
  });
}

/// 评分失败
class SourceRatingError implements Exception {
  final String message;
  SourceRatingError(this.message);
  @override
  String toString() => message;
}

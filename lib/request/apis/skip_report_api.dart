import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/logging/logger.dart';

/// 众包跳过统计 API（对接 qlyyz.xyz/api/skip.php）
///
/// - [report]：上报该番片头/片尾时长（手动设置时）
/// - [fetch]：拉取该番众包时长（未手动设置时自动应用）
class SkipReportApi {
  SkipReportApi._();

  static const String baseUrl = 'https://qlyyz.xyz/api/skip.php';

  /// 上报：opMs/edMs 为该番片头/片尾毫秒（0 表示无）
  static Future<void> report({
    required int subjectId,
    required int opMs,
    required int edMs,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request =
          await client.postUrl(Uri.parse('$baseUrl?action=report'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode(jsonEncode({
        'subjectId': subjectId,
        'opMs': opMs,
        'edMs': edMs,
      })));
      await request.close();
      client.close();
    } catch (e) {
      KazumiLogger().w('SkipReport: 上报失败', error: e);
    }
  }

  /// 拉取众包时长；返回 (opMs, edMs)，无数据时均为 0
  static Future<({int opMs, int edMs})?> fetch(int subjectId) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client
          .getUrl(Uri.parse('$baseUrl?action=get&id=$subjectId'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['success'] != true) return null;
      return (
        opMs: (json['opMs'] as num?)?.toInt() ?? 0,
        edMs: (json['edMs'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      KazumiLogger().w('SkipReport: 拉取失败', error: e);
      return null;
    }
  }
}

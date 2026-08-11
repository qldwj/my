import 'dart:convert';
import 'dart:io';

import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 自建弹幕条目
class CustomDanmakuItem {
  const CustomDanmakuItem({
    required this.id,
    required this.timeMs,
    required this.text,
    this.sender = '',
    this.type = 1,
    this.votes = 0,
  });

  final int id;
  final int timeMs;
  final String text;
  final String sender;
  final int type; // 1=滚动 4=底部 5=顶部
  final int votes;

  factory CustomDanmakuItem.fromJson(Map<String, dynamic> json) {
    return CustomDanmakuItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      timeMs: (json['time'] as num?)?.toInt() ?? 0,
      text: json['text']?.toString() ?? '',
      sender: json['sender']?.toString() ?? '',
      type: (json['type'] as num?)?.toInt() ?? 1,
      votes: (json['votes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 自建弹幕 API（对接 qlyyz.xyz/api/danmaku.php）
///
/// - 发送弹幕（服务端过滤网址 + 待审核）
/// - 拉取已审核弹幕（同番同集）
class CustomDanmakuApi {
  CustomDanmakuApi._();

  static const String baseUrl = ApiEndpoints.danmakuApi;

  /// 发送弹幕到自己的服务器（含网址会被拒绝）
  /// [type] 1=滚动 4=底部(置底) 5=顶部(置顶)
  static Future<String?> send({
    required int bangumiId,
    required int episode,
    required int timeMs,
    required String text,
    String sender = '',
    int type = 1,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.postUrl(Uri.parse('$baseUrl?action=add'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode(jsonEncode({
        'bangumiId': bangumiId,
        'episode': episode,
        'time': timeMs,
        'text': text,
        'sender': sender,
        'type': type,
      })));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['success'] == true) {
        return null; // 成功
      }
      return json['error']?.toString() ?? '发送失败';
    } catch (e) {
      KazumiLogger().e('CustomDanmaku: 发送失败', error: e);
      return '网络异常';
    }
  }

  /// 弹幕点赞
  static Future<void> vote(int id) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(Uri.parse('$baseUrl?action=vote'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode(jsonEncode({'id': id})));
      await request.close();
      client.close();
    } catch (e) {
      KazumiLogger().w('CustomDanmaku: 点赞失败', error: e);
    }
  }

  /// 拉取该番该集的已审核弹幕
  static Future<List<CustomDanmakuItem>> fetch({
    required int bangumiId,
    required int episode,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(
          '$baseUrl?action=list&id=$bangumiId&ep=$episode'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final list = json['danmakus'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => CustomDanmakuItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      KazumiLogger().e('CustomDanmaku: 拉取失败', error: e);
      return const [];
    }
  }
}

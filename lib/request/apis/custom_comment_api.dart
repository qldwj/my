import 'dart:convert';
import 'dart:io';

import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 自建评论条目
class CustomCommentItem {
  const CustomCommentItem({
    required this.id,
    required this.text,
    required this.sender,
    required this.votes,
    required this.createdAt,
    this.parentId = 0,
  });

  final int id;
  final String text;
  final String sender;
  final int votes;
  final int createdAt;
  final int parentId;

  factory CustomCommentItem.fromJson(Map<String, dynamic> json) {
    return CustomCommentItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      text: json['text']?.toString() ?? '',
      sender: json['sender']?.toString() ?? '',
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      parentId: (json['parentId'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 自建评论 API（对接 qlyyz.xyz/api/comment.php）
///
/// 来源 source='server'；我的服务器评论优先于 Bangumi 评论显示
class CustomCommentApi {
  CustomCommentApi._();

  static const String baseUrl = 'https://qlyyz.xyz/api/comment.php';

  static Future<Map<String, dynamic>> _post(
    String action,
    Map<String, dynamic> body,
  ) async {
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
      return jsonDecode(resp) as Map<String, dynamic>;
    } catch (e) {
      KazumiLogger().e('CustomComment: 请求失败', error: e);
      return {'success': false, 'error': '网络异常'};
    }
  }

  /// 发表评论（episode=0 条目评论，>0 剧集评论）
  static Future<String?> add({
    required int subjectId,
    required String text,
    int episode = 0,
    String sender = '',
  }) async {
    final res = await _post('add', {
      'subjectId': subjectId,
      'episode': episode,
      'text': text,
      'sender': sender,
    });
    if (res['success'] == true) return null;
    return res['error']?.toString() ?? '发表失败';
  }

  /// 拉取该番（该集）的服务器评论
  static Future<List<CustomCommentItem>> fetch({
    required int subjectId,
    int episode = 0,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(
          Uri.parse('$baseUrl?action=list&id=$subjectId&ep=$episode'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final list = json['comments'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => CustomCommentItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      KazumiLogger().e('CustomComment: 拉取失败', error: e);
      return const [];
    }
  }
}

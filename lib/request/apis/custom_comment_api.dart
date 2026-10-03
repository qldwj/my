import 'dart:convert';
import 'dart:io';

import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 自建评论条目
class CustomCommentItem {
  const CustomCommentItem({
    required this.id,
    required this.text,
    required this.sender,
    required this.votes,
    required this.createdAt,
    this.rating = 0,
    this.uid = '',
    this.avatar = '',
    this.parentId = 0,
    this.pinned = false,
    this.title = '',
    this.coins = 0,
  });

  final int id;
  final String text;
  final String sender;
  final int votes;
  final int createdAt;

  /// 打分 0-10（0 = 未评分）
  final int rating;

  /// 评论者 uid / 头像（用于显示头像）
  final String uid;
  final String avatar;
  final int parentId;
  final bool pinned;

  /// 🆕 评论者称号（已解锁自选）/ 积分（签到 coins）
  final String title;
  final int coins;

  factory CustomCommentItem.fromJson(Map<String, dynamic> json) {
    return CustomCommentItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      text: json['text']?.toString() ?? '',
      sender: json['sender']?.toString() ?? '',
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      uid: json['uid']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      parentId: (json['parentId'] as num?)?.toInt() ?? 0,
      pinned: (json['pinned'] as num?)?.toInt() == 1,
      title: json['title']?.toString() ?? '',
      coins: (json['coins'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 自建评论 API（对接 qlyyz.xyz/api/v0/comment.php）
///
/// 来源 source='server'；我的服务器评论优先于 Bangumi 评论显示
class CustomCommentApi {
  CustomCommentApi._();

  static const String baseUrl = 'https://qlyyz.xyz/api/v0/comment.php';

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
      // 🆕 带上 Bearer token（后端 verifyUser 需要）
      final token = AuthService.getLocalToken();
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }
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

  /// 发表评论（episode=0 条目评论，>0 剧集评论；rating 0-10，0=不评分）
  /// [uid]/[avatar]/[sender] 来自登录用户资料，用于评论显示头像和昵称
  static Future<String?> add({
    required int subjectId,
    required String text,
    int episode = 0,
    String sender = '',
    int rating = 0,
    String uid = '',
    String avatar = '',
  }) async {
    final res = await _post('add', {
      'subjectId': subjectId,
      'episode': episode,
      'text': text,
      'sender': sender,
      'rating': rating.clamp(0, 10),
      'uid': uid,
      'avatar': avatar,
    });
    if (res['success'] == true) return null;
    return res['error']?.toString() ?? '发表失败';
  }

  /// 拉取该番（该集）的服务器评论；返回评论列表 + 管理员昵称
  static Future<({List<CustomCommentItem> items, String adminNickname})>
      fetch({    required int subjectId,
    int episode = 0,
  }) async {
    String body = '';
    int statusCode = 0;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(
          Uri.parse('$baseUrl?action=list&id=$subjectId&ep=$episode'));
      final response = await request.close();
      statusCode = response.statusCode;
      body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final list = json['comments'];
      if (list is! List) {
        return (items: const <CustomCommentItem>[], adminNickname: '');
      }
      final items = list
          .whereType<Map>()
          .map((e) => CustomCommentItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final nick = json['admin_nickname']?.toString() ?? '';
      return (items: items, adminNickname: nick);
    } catch (e) {
      // 🆕 记录状态码 + 响应原文，便于判断 Kangle 验证页 / 空响应 / 正常 JSON
      final preview = body.length > 800 ? body.substring(0, 800) : body;
      KazumiLogger().e('CustomComment: 拉取失败 status=$statusCode',
          error: e, forceLog: true);
      KazumiLogger().w('CustomComment: 响应原文: $preview', forceLog: true);
      return (items: const <CustomCommentItem>[], adminNickname: '');
    }
  }

  /// 🆕 举报评论（长按评论触发）
  static Future<String?> report({
    required int commentId,
    required String reason,
  }) async {
    final res = await _post('report', {'commentId': commentId, 'reason': reason});
    if (res['success'] == true) return null;
    return res['error']?.toString() ?? '举报失败';
  }
}

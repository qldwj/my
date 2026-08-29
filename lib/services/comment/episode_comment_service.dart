import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kazumi/models/episode_comment.dart';
import 'package:kazumi/services/auth_service.dart';

class EpisodeCommentService {
  static const String _baseUrl = 'https://qlyyz.xyz/api/episode_comment.php';

  static Future<Map<String, dynamic>> addComment({
    required int subjectId, required int episode, required String content, String? avatar,
  }) async {
    final token = AuthService.getLocalToken();
    if (token == null) return {'success': false, 'error': '请先登录'};
    final res = await http.post(Uri.parse('$_baseUrl?action=add'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'subjectId': subjectId, 'episode': episode, 'content': content, 'avatar': avatar ?? ''}));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> replyComment({required int commentId, required String content}) async {
    final token = AuthService.getLocalToken();
    if (token == null) return {'success': false, 'error': '请先登录'};
    final res = await http.post(Uri.parse('$_baseUrl?action=reply'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'commentId': commentId, 'content': content}));
    return jsonDecode(res.body);
  }

  static Future<List<EpisodeComment>> getComments({required int subjectId, int episode = 0, String sort = 'time'}) async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl?action=list&id=$subjectId&ep=$episode&sort=$sort'));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        return (data['data'] as List).map((e) => EpisodeComment.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> vote({required int commentId, required int value}) async {
    final token = AuthService.getLocalToken();
    if (token == null) return {'success': false, 'error': '请先登录'};
    final res = await http.post(Uri.parse('$_baseUrl?action=vote'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'commentId': commentId, 'value': value}));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> react({required int commentId, required String sticker}) async {
    final token = AuthService.getLocalToken();
    if (token == null) return {'success': false, 'error': '请先登录'};
    final res = await http.post(Uri.parse('$_baseUrl?action=react'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'commentId': commentId, 'sticker': sticker}));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> removeComment(int commentId) async {
    final token = AuthService.getLocalToken();
    if (token == null) return {'success': false, 'error': '请先登录'};
    final res = await http.post(Uri.parse('$_baseUrl?action=remove'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'commentId': commentId}));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> reportComment({required int commentId, required String reason}) async {
    final token = AuthService.getLocalToken();
    if (token == null) return {'success': false, 'error': '请先登录'};
    final res = await http.post(Uri.parse('$_baseUrl?action=report'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'commentId': commentId, 'reason': reason}));
    return jsonDecode(res.body);
  }

  static Future<List<Map<String, String>>> getStickers() async {
    final res = await http.get(Uri.parse('$_baseUrl?action=stickers'));
    final data = jsonDecode(res.body);
    if (data['success'] == true) return List<Map<String, String>>.from(data['data'] ?? []);
    return [];
  }
}

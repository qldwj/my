import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kazumi/services/auth_service.dart';

/// 工单
class Ticket {
  final int id;
  final String type;
  final String typeName;
  final String subjectName;
  final String ep;
  final String content;
  final String status;
  final String statusName;
  final String adminReply;
  final int createdAt;

  Ticket.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num?)?.toInt() ?? 0,
        type = j['type']?.toString() ?? 'other',
        typeName = j['type_name']?.toString() ?? '',
        subjectName = j['subject_name']?.toString() ?? '',
        ep = j['ep']?.toString() ?? '',
        content = j['content']?.toString() ?? '',
        status = j['status']?.toString() ?? 'pending',
        statusName = j['status_name']?.toString() ?? '待处理',
        adminReply = j['admin_reply']?.toString() ?? '',
        createdAt = (j['created_at'] as num?)?.toInt() ?? 0;

  String get timeAgo {
    final diff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - createdAt;
    if (diff < 60) return '刚刚';
    if (diff < 3600) return '${diff ~/ 60}分钟前';
    if (diff < 86400) return '${diff ~/ 3600}小时前';
    return '${diff ~/ 86400}天前';
  }
}

/// 工单服务（对接 /api/v1/ticket.php）
class TicketService {
  static const String api = 'https://qlyyz.xyz/api/v1/ticket.php';

  static const List<({String id, String name})> types = [
    (id: 'source_fail', name: '源失效'),
    (id: 'missing_ep', name: '缺集'),
    (id: 'subtitle', name: '字幕错误'),
    (id: 'quality', name: '画质异常'),
    (id: 'other', name: '其他问题'),
  ];

  static String? _token() => AuthService.getLocalToken();

  /// 提交工单
  static Future<Map<String, dynamic>> add({
    required String type,
    required String content,
    int subjectId = 0,
    String subjectName = '',
    String ep = '',
    String image = '',
  }) async {
    final token = _token();
    if (token == null) return {'success': false, 'error': '请先登录'};
    try {
      final res = await http.post(Uri.parse('$api?action=add'), body: {
        'token': token, 'type': type, 'content': content,
        'subject_id': '$subjectId', 'subject_name': subjectName,
        'ep': ep, 'image': image,
      });
      final j = jsonDecode(res.body);
      return j is Map ? Map<String, dynamic>.from(j) : {'success': false};
    } catch (e) {
      return {'success': false, 'error': '网络错误'};
    }
  }

  /// 我的工单列表
  static Future<List<Ticket>> my() async {
    final token = _token();
    if (token == null) return [];
    try {
      final res = await http.get(Uri.parse('$api?action=my&token=$token'));
      final j = jsonDecode(res.body);
      if (j is Map && j['success'] == true && j['list'] is List) {
        return (j['list'] as List)
            .map((e) => Ticket.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 规则市场条目（来自 json 文件仓库 record）
class MarketRuleItem {
  const MarketRuleItem({
    required this.file,
    required this.origin,
    required this.uid,
    required this.isAdminUpload,
    required this.time,
    this.category = '其他',
  });

  final String file;
  final String origin;
  final String uid;
  final bool isAdminUpload;
  final String time;
  final String category;

  factory MarketRuleItem.fromJson(Map<String, dynamic> json) {
    return MarketRuleItem(
      file: json['file']?.toString() ?? '',
      origin: json['origin']?.toString() ?? '',
      uid: json['uid']?.toString() ?? '',
      isAdminUpload: json['is_admin_upload'] == true,
      time: json['time']?.toString() ?? '',
      category: json['category']?.toString().isNotEmpty == true
          ? json['category'].toString()
          : '其他',
    );
  }
}

/// 规则市场 API（对接 https://qlyyz.xyz/json/ 文件仓库）
///
/// 接口约定（见 json/api.php）：
/// - list   → 文件列表（区分管理员上传 / 用户上传）
/// - read   → 读取规则内容（用于安装）
/// - upload → 上传规则（任何人可传，游客记为"用户上传"）
/// - del    → 下架（仅管理员，通过网页端操作）
class PluginMarketApi {
  PluginMarketApi._();

  static const String baseUrl = ApiEndpoints.pluginMarketApi;

  /// 获取规则市场列表
  static Future<List<MarketRuleItem>> fetchList() async {
    final res = await _post({'act': 'list'});
    final code = res['code'];
    if (code != 1) {
      throw Exception('获取市场列表失败: ${res['msg'] ?? code}');
    }
    final list = res['list'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => MarketRuleItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 读取规则内容（JSON 字符串，可直接交给 Plugin.fromJson）
  static Future<String> fetchRule(String file) async {
    final res = await _post({'act': 'read', 'file': file});
    final code = res['code'];
    if (code != 1) {
      throw Exception('读取规则失败: ${res['msg'] ?? code}');
    }
    final data = res['data'];
    return data?.toString() ?? '';
  }

  /// 上传规则到市场（任何人均可上传；管理员登录后上传会标记为管理员上传）
  ///
  /// [name] 规则名（用作文件名），[content] 规则 JSON 字符串，
  /// [category] 来源站分类（如 樱花 / 樱花动漫 / 其他）
  static Future<String> uploadRule({
    required String name,
    required String content,
    String category = '其他',
  }) async {
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final boundary = '----kazumi${DateTime.now().millisecondsSinceEpoch}';
    final safeContent =
        content.replaceAll('--', '--').replaceAll('$boundary', '_');
    final body = StringBuffer();
    body
      ..write('--$boundary\r\n')
      ..write('Content-Disposition: form-data; name="act"\r\n\r\n')
      ..write('upload\r\n')
      ..write('--$boundary\r\n')
      ..write('Content-Disposition: form-data; name="category"\r\n\r\n')
      ..write(category)
      ..write('\r\n')
      ..write('--$boundary\r\n')
      ..write(
          'Content-Disposition: form-data; name="jsonfile"; filename="$safeName.json"\r\n')
      ..write('Content-Type: application/json\r\n\r\n')
      ..write(safeContent)
      ..write('\r\n--$boundary--\r\n');

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      final request =
          await client.postUrl(Uri.parse(baseUrl));
      request.headers
          .set('Content-Type', 'multipart/form-data; boundary=$boundary');
      request.add(utf8.encode(body.toString()));
      final response = await request.close();
      final responseBody =
          await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final code = json['code'];
      if (code != 1) {
        return '❌ 上传失败: ${json['msg'] ?? code}';
      }
      return '✅ 已上传到市场（${json['msg'] ?? ''}）';
    } catch (e) {
      KazumiLogger().e('PluginMarketApi: 上传失败', error: e);
      return '❌ 上传失败: $e';
    }
  }

  static Future<Map<String, dynamic>> _post(
    Map<String, dynamic> form, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = timeout;
      final request = await client.postUrl(Uri.parse(baseUrl));
      request.headers.set('Content-Type',
          'application/x-www-form-urlencoded; charset=utf-8');
      request.add(utf8.encode(uriEncode(form)));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      KazumiLogger().e('PluginMarketApi: 请求失败', error: e);
      throw Exception('网络请求失败: $e');
    }
  }

  static String uriEncode(Map<String, dynamic> form) {
    return form.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value?.toString() ?? '')}')
        .join('&');
  }
}

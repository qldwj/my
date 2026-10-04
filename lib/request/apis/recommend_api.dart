import 'dart:convert';
import 'dart:io';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

/// 首页推荐接口（代理 Animeko 官方 /v2/home/recommendations）
/// 后端：https://qlyyz.xyz/api/v0/recommendations.php?offset=&limit=
class RecommendApi {
  static const String _baseUrl =
      'https://qlyyz.xyz/api/v0/recommendations.php';

  /// 拉取一页推荐，失败返回空列表（调用方静默降级）
  static Future<List<BangumiItem>> fetchRecommendations({
    int offset = 0,
    int limit = 20,
  }) async {
    final url = '$_baseUrl?offset=$offset&limit=$limit';
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'CycAndroid/5.6.1');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final json = jsonDecode(body);
      if (json is! Map<String, dynamic> || json['data'] == null) {
        return [];
      }
      final list = json['data']['list'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => _toBangumiItem(Map<String, dynamic>.from(e)))
          .where((item) => item.id > 0)
          .toList();
    } catch (e) {
      return [];
    }
  }

  static BangumiItem _toBangumiItem(Map<String, dynamic> e) {
    final image = (e['image'] ?? '').toString();
    final nameCn = (e['nameCn'] ?? '').toString();
    final name = (e['name'] ?? '').toString();
    return BangumiItem(
      id: (e['id'] is num) ? (e['id'] as num).toInt() : 0,
      type: 2,
      name: name,
      nameCn: nameCn.isEmpty ? name : nameCn,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {
        'large': image,
        'common': image,
        'medium': image,
        'small': image,
        'grid': image,
      },
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );
  }
}

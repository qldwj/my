import 'dart:convert';
import 'dart:io';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';

/// 首页推荐接口（代理 Animeko 官方 /v2/home/recommendations）
/// 后端：https://qlyyz.xyz/api/v0/recommendations.php?offset=&limit=
class RecommendApi {
  static const String _baseUrl =
      'https://qlyyz.xyz/api/v0/recommendations';

  /// 拉取一页推荐。失败静默降级为空列表。
  /// 返回 (list, hasMore)，供无限分页使用。
  static Future<({List<BangumiItem> list, bool hasMore})> fetchRecommendations({
    int offset = 0,
    int limit = 20,
  }) async {
    // 首页优先读本地缓存，避免每次进首页都触发服务器验证
    if (offset == 0) {
      final cached = GStorage.getSetting(SettingsKeys.recommendHomeCache);
      if (cached is String && cached.isNotEmpty) {
        try {
          final decoded = jsonDecode(cached);
          if (decoded is List) {
            final items = decoded
                .whereType<Map>()
                .map((e) => _toBangumiItem(Map<String, dynamic>.from(e)))
                .where((item) => item.id > 0)
                .toList();
            if (items.isNotEmpty) return (list: items, hasMore: true);
          }
        } catch (_) {
          // 缓存损坏则忽略，走网络重新拉取
        }
      }
    }

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
        return (list: const <BangumiItem>[], hasMore: false);
      }
      final data = json['data'];
      if (data is! Map<String, dynamic>) {
        return (list: const <BangumiItem>[], hasMore: false);
      }
      final list = data['list'];
      if (list is! List) return (list: const <BangumiItem>[], hasMore: false);
      final items = list
          .whereType<Map>()
          .map((e) => _toBangumiItem(Map<String, dynamic>.from(e)))
          .where((item) => item.id > 0)
          .toList();
      // 首页成功拉取后写入缓存
      if (offset == 0 && items.isNotEmpty) {
        GStorage.putSetting(SettingsKeys.recommendHomeCache, jsonEncode(list));
      }
      final hasMore = data['has_more'] == true;
      return (list: items, hasMore: hasMore);
    } catch (e) {
      return (list: const <BangumiItem>[], hasMore: false);
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
      summary: (e['desc2'] ?? '').toString(),
      airDate: (e['desc1'] ?? '').toString(),
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

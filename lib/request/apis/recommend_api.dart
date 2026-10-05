import 'dart:convert';
import 'dart:io';
import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/storage/settings_keys.dart';

/// 首页推荐接口（代理 Animeko 官方 /v2/home/recommendations）
/// 后端：https://qlyyz.xyz/api/v0/recommendations.php?offset=&limit=
class RecommendApi {
  static const String _baseUrl =
      'https://qlyyz.xyz/api/v0/recommendations';

  /// 单页拉取条数：一次拉满 100 条，减少请求次数（服务器风控友好），
  /// 缓存后横向基本可无限滑动，滑到尽头再增量请求。
  static const int pageLimit = 100;

  /// 服务器推荐总量（用于推断 hasMore）
  static const int serverTotal = 200;

  /// 同步读取本地缓存（首页首帧直达，不闪加载）。
  /// 无缓存/损坏时返回 null。
  static List<BangumiItem>? cachedItems() {
    final cached = GStorage.getSetting(SettingsKeys.recommendHomeCache);
    if (cached is! String || cached.isEmpty) return null;
    try {
      final decoded = jsonDecode(cached);
      if (decoded is! List) return null;
      final items = decoded
          .whereType<Map>()
          .map((e) => _toBangumiItem(Map<String, dynamic>.from(e)))
          .where((item) => item.id > 0)
          .toList();
      return items.isEmpty ? null : items;
    } catch (_) {
      return null; // 缓存损坏则忽略，走网络重新拉取
    }
  }

  /// 拉取一页推荐。
  /// 返回 (list, hasMore, ok)：ok=false 表示网络/解析失败（与"没有更多"区分，
  /// 上层应保留继续加载能力，避免服务器风控时推荐"加载到一半就没了"）。
  static Future<({List<BangumiItem> list, bool hasMore, bool ok})> fetchRecommendations({
    int offset = 0,
    int limit = pageLimit,
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
        return (list: const <BangumiItem>[], hasMore: false, ok: true);
      }
      final data = json['data'];
      if (data is! Map<String, dynamic>) {
        return (list: const <BangumiItem>[], hasMore: false, ok: true);
      }
      final list = data['list'];
      if (list is! List) {
        return (list: const <BangumiItem>[], hasMore: false, ok: true);
      }
      final items = list
          .whereType<Map>()
          .map((e) => _toBangumiItem(Map<String, dynamic>.from(e)))
          .where((item) => item.id > 0)
          .toList();
      // 首页成功拉取后写入缓存（合并已加载过的条目，避免重复请求）
      if (offset == 0 && items.isNotEmpty) {
        GStorage.putSetting(SettingsKeys.recommendHomeCache, jsonEncode(list));
      }
      final hasMore = data['has_more'] == true;
      return (list: items, hasMore: hasMore, ok: true);
    } catch (e) {
      // 网络失败：ok=false，上层保留继续加载能力
      return (list: const <BangumiItem>[], hasMore: true, ok: false);
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

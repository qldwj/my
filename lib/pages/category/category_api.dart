import 'dart:convert';
import 'dart:io';

/// 次元城分类代理接口数据层（category.php，无签名，30 分钟后端缓存）
class CategoryApi {
  static const String base = 'https://qlyyz.xyz/api/v0/category.php';

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _receiveTimeout = Duration(seconds: 20);

  /// 拉取分类列表
  static Future<List<CategoryZone>> fetchZones() async {
    final uri = Uri.parse('$base?action=zones');
    final body = await _get(uri);
    if (body == null) return [];
    final data = jsonDecode(body);
    final list = (data['data']?['list'] as List?) ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(CategoryZone.fromJson)
        .toList();
  }

  /// 拉取分类视频（支持标签 / 年份筛选，分页）
  static Future<List<CategoryVideo>> fetchVideos({
    required int zoneId,
    String category = '',
    int year = 0,
    int page = 1,
    int limit = 24,
  }) async {
    final query = <String, dynamic>{
      'action': 'videos',
      'zone_id': zoneId,
      'page': page,
      'limit': limit,
    };
    if (category.isNotEmpty) query['category'] = category;
    if (year > 0) query['year'] = year;
    final uri = Uri.parse('$base?${Uri(queryParameters: query).query}');
    final body = await _get(uri);
    if (body == null) return [];
    final data = jsonDecode(body);
    final list = (data['data']?['list'] as List?) ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(CategoryVideo.fromJson)
        .toList();
  }

  /// 拉取视频详情（含真实 bangumi_id，用于跳转 Bangumi 详情页）
  static Future<CategoryVideoDetail?> fetchVideoDetail(int videoId) async {
    final uri = Uri.parse('$base?action=detail&video_id=$videoId');
    final body = await _get(uri);
    if (body == null) return null;
    final data = jsonDecode(body);
    final d = data['data'];
    if (d is! Map<String, dynamic>) return null;
    return CategoryVideoDetail.fromJson(d);
  }

  static Future<String?> _get(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(_receiveTimeout);
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}

/// 分类（含标签 / 年份筛选项）
class CategoryZone {
  final int id;
  final String name;
  final List<String> categories;
  final List<String> years;

  CategoryZone({
    required this.id,
    required this.name,
    required this.categories,
    required this.years,
  });

  factory CategoryZone.fromJson(Map<String, dynamic> j) {
    final filters = (j['filters'] as Map?) ?? const {};
    return CategoryZone(
      id: (j['id'] as num?)?.toInt() ?? 0,
      name: (j['name'] as String?) ?? '',
      categories: _strList(filters['categories']),
      years: _strList(filters['years']),
    );
  }

  static List<String> _strList(dynamic v) {
    if (v is! List) return [];
    return v.map((e) => e.toString()).toList();
  }
}

/// 分类视频条目
class CategoryVideo {
  final int videoId;
  final String title;
  final String coverUrl;
  final int year;
  final double score;
  final int hits;
  final String remarks;
  final String area;
  final String version;

  CategoryVideo({
    required this.videoId,
    required this.title,
    required this.coverUrl,
    required this.year,
    required this.score,
    required this.hits,
    required this.remarks,
    required this.area,
    required this.version,
  });

  factory CategoryVideo.fromJson(Map<String, dynamic> j) {
    return CategoryVideo(
      videoId: (j['video_id'] as num?)?.toInt() ?? 0,
      title: (j['title'] as String?) ?? '',
      coverUrl: (j['cover_url'] as String?) ?? '',
      year: (j['year'] as num?)?.toInt() ?? 0,
      score: (j['score'] as num?)?.toDouble() ?? 0,
      hits: (j['hits'] as num?)?.toInt() ?? 0,
      remarks: (j['remarks'] as String?) ?? '',
      area: (j['area'] as String?) ?? '',
      version: (j['version'] as String?) ?? '',
    );
  }
}

/// 分类视频详情（含真实 bangumi_id，用于跳转 Bangumi 详情页）
class CategoryVideoDetail {
  final int videoId;
  final int bangumiId;
  final String title;
  final String coverUrl;
  final int year;
  final double score;
  final String description;

  CategoryVideoDetail({
    required this.videoId,
    required this.bangumiId,
    required this.title,
    required this.coverUrl,
    required this.year,
    required this.score,
    required this.description,
  });

  factory CategoryVideoDetail.fromJson(Map<String, dynamic> j) {
    return CategoryVideoDetail(
      videoId: (j['id'] as num?)?.toInt() ?? 0,
      bangumiId: (j['bangumi_id'] as num?)?.toInt() ?? 0,
      title: (j['title'] as String?) ?? '',
      coverUrl: (j['cover_url'] as String?) ?? '',
      year: (j['year'] as num?)?.toInt() ?? 0,
      score: (j['score'] as num?)?.toDouble() ?? 0,
      description: (j['description'] as String?) ?? '',
    );
  }
}

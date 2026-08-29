import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/subject_relation.dart';
import 'package:kazumi/modules/comments/comment_response.dart';
import 'package:kazumi/modules/characters/characters_response.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/character/character_full_item.dart';
import 'package:kazumi/modules/staff/staff_response.dart';
import 'package:kazumi/modules/bangumi/bangumi_collection.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/collect/collect_type_mapper.dart';
import 'package:kazumi/modules/bangumi/bangumi_collection_type.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:kazumi/utils/search_parser.dart';

class BangumiSearchPage {
  const BangumiSearchPage({
    required this.items,
    required this.rawCount,
  });

  final List<BangumiItem> items;
  final int rawCount;
}

class BangumiApi {
  static final BangumiClient _client = BangumiClient.instance;

  /// 通过代理请求 Bangumi API（仅在开启 Bangumi 镜像时使用，仅用于评论）
  static const String _proxyBase = 'https://qlyyz.xyz/api/proxy';
  static bool get _proxyEnabled =>
      GStorage.getSetting(SettingsKeys.enableBangumiProxy);

  static Future<dynamic> _proxyGet(String originalUrl) async {
    if (!_proxyEnabled) {
      return _client.get(originalUrl);
    }
    final encoded = base64Encode(utf8.encode(originalUrl));
    final proxyUrl = '$_proxyBase?url=$encoded';
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final appId = bangumiMirrorCredentials['id'] ?? '';
    final appKey = bangumiMirrorCredentials['value'] ?? '';
    final bodyStr = '';
    final data = utf8.encode('$appId$timestamp$bodyStr$appKey');
    final digest = sha256.convert(data);
    final signature = base64Encode(digest.bytes);

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(proxyUrl));
      request.headers.set('X-AppId', appId);
      request.headers.set('X-Timestamp', timestamp.toString());
      request.headers.set('X-Signature', signature);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      return jsonDecode(body);
    } catch (e) {
      KazumiLogger().e('Proxy request failed, fallback to direct', error: e);
      return _client.get(originalUrl);
    }
  }

  static Future<List<List<BangumiItem>>> getCalendar() async {
    List<List<BangumiItem>> bangumiCalendar = [];
    try {
      final jsonData = await _client.get(
        ApiEndpoints.bangumiAPINextDomain + ApiEndpoints.bangumiCalendar,
      );
      for (int i = 1; i <= 7; i++) {
        List<BangumiItem> bangumiList = [];
        final jsonList = jsonData['$i'];
        for (dynamic jsonItem in jsonList) {
          try {
            BangumiItem bangumiItem = BangumiItem.fromJson(jsonItem['subject']);
            bangumiList.add(bangumiItem);
          } catch (_) {}
        }
        bangumiCalendar.add(bangumiList);
      }
    } catch (e) {
      KazumiLogger().e('Resolve calendar failed', error: e);
    }
    return bangumiCalendar;
  }

  // Official fallback for season switching. Mirror mode uses the cached
  // /kazumi/v1/calendar/season endpoint instead of Bangumi search.
  static Future<List<List<BangumiItem>>> getCalendarBySearch(
      List<String> dateRange, int limit, int offset) async {
    List<BangumiItem> bangumiList = [];
    List<List<BangumiItem>> bangumiCalendar = [];
    var params = <String, dynamic>{
      "keyword": "",
      "sort": "rank",
      "filter": {
        "type": [2],
        "tag": ["日本"],
        "air_date": [">=${dateRange[0]}", "<${dateRange[1]}"],
        "rank": [">0", "<=99999"],
        "nsfw": true
      }
    };
    try {
      final url = ApiEndpoints.formatUrl(
          ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRankSearch,
          [limit, offset]);
      final jsonData = await _client.post(
        url,
        data: params,
      );
      final jsonList = jsonData['data'];
      for (dynamic jsonItem in jsonList) {
        if (jsonItem is Map<String, dynamic>) {
          bangumiList.add(BangumiItem.fromJson(jsonItem));
        }
      }
    } catch (e) {
      KazumiLogger().e('Resolve bangumi list failed', error: e);
    }
    try {
      for (int weekday = 1; weekday <= 7; weekday++) {
        List<BangumiItem> bangumiDayList = [];
        for (BangumiItem bangumiItem in bangumiList) {
          if (bangumiItem.airWeekday == weekday) {
            bangumiDayList.add(bangumiItem);
          }
        }
        bangumiCalendar.add(bangumiDayList);
      }
    } catch (e) {
      KazumiLogger()
          .e('Network: fetch bangumi item to calendar failed', error: e);
    }
    return bangumiCalendar;
  }

  static String buildBangumiMirrorSeasonCalendarPath(List<String> dateRange) {
    return Uri(
      path: ApiEndpoints.bangumiMirrorSeasonCalendar,
      queryParameters: {
        'start': dateRange[0],
        'end': dateRange[1],
      },
    ).toString();
  }

  static Future<List<List<BangumiItem>>> getBangumiMirrorSeasonCalendar(
      List<String> dateRange) async {
    List<List<BangumiItem>> bangumiCalendar = [];
    try {
      final jsonData = await _client.get(
        ApiEndpoints.bangumiMirrorDomain +
            buildBangumiMirrorSeasonCalendarPath(dateRange),
      );
      for (int i = 1; i <= 7; i++) {
        List<BangumiItem> bangumiList = [];
        final jsonList = jsonData['$i'] ?? [];
        for (dynamic jsonItem in jsonList) {
          try {
            final subject =
                jsonItem is Map<String, dynamic> ? jsonItem['subject'] : null;
            if (subject is Map<String, dynamic>) {
              bangumiList.add(BangumiItem.fromJson(subject));
            }
          } catch (_) {}
        }
        bangumiCalendar.add(bangumiList);
      }
    } catch (e) {
      KazumiLogger().e('Network: resolve bangumi mirror season calendar failed',
          error: e);
    }
    return bangumiCalendar;
  }

  static Future<List<BangumiItem>> getBangumiList(
      {int rank = 2, String tag = ''}) async {
    List<BangumiItem> bangumiList = [];
    late Map<String, dynamic> params;
    if (tag == '') {
      params = <String, dynamic>{
        'keyword': '',
        'sort': 'rank',
        "filter": {
          "type": [2],
          "tag": ["日本"],
          "rank": [">$rank", "<=1050"],
          "nsfw": false
        },
      };
    } else {
      params = <String, dynamic>{
        'keyword': '',
        'sort': 'rank',
        "filter": {
          "type": [2],
          "tag": [tag],
          "rank": [">$rank", "<=99999"],
          "nsfw": false
        },
      };
    }
    try {
      final jsonData = await _client.post(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRankSearch,
            [100, 0]),
        data: params,
      );
      final jsonList = jsonData['data'];
      for (dynamic jsonItem in jsonList) {
        if (jsonItem is Map<String, dynamic>) {
          bangumiList.add(BangumiItem.fromJson(jsonItem));
        }
      }
    } catch (e) {
      KazumiLogger().e('Network: resolve bangumi list failed', error: e);
    }
    return bangumiList;
  }

  static Future<List<BangumiItem>> getBangumiTrendsList(
      {int type = 2, int limit = 24, int offset = 0}) async {
    List<BangumiItem> bangumiList = [];
    var params = <String, dynamic>{
      'type': type,
      'limit': limit,
      'offset': offset,
    };
    try {
      final jsonData = await _client.get(
        ApiEndpoints.bangumiAPINextDomain + ApiEndpoints.bangumiTrendsNext,
        queryParameters: params,
      );
      final jsonList = jsonData['data'];
      for (dynamic jsonItem in jsonList) {
        if (jsonItem is Map<String, dynamic>) {
          bangumiList.add(BangumiItem.fromJson(jsonItem['subject']));
        }
      }
    } catch (e) {
      KazumiLogger().e('Network: resolve bangumi trends list failed', error: e);
    }
    return bangumiList;
  }

  static String buildBangumiMirrorPopularPath({
    String tag = '',
    int limit = 24,
    int offset = 0,
  }) {
    return Uri(
      path: ApiEndpoints.bangumiMirrorPopularSubjects,
      queryParameters: {
        if (tag.isNotEmpty) 'tag': tag,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    ).toString();
  }

  static Future<List<BangumiItem>> getBangumiMirrorPopularSubjects({
    String tag = '',
    int limit = 24,
    int offset = 0,
  }) async {
    List<BangumiItem> bangumiList = [];
    try {
      final jsonData = await _client.get(
        ApiEndpoints.bangumiMirrorDomain +
            buildBangumiMirrorPopularPath(
              tag: tag,
              limit: limit,
              offset: offset,
            ),
      );
      final jsonList = jsonData is List ? jsonData : jsonData['data'];
      for (dynamic jsonItem in jsonList) {
        if (jsonItem is Map<String, dynamic>) {
          bangumiList.add(BangumiItem.fromJson(jsonItem));
        }
      }
    } catch (e) {
      KazumiLogger()
          .e('Network: resolve bangumi mirror popular list failed', error: e);
    }
    return bangumiList;
  }

  static List<String> _buildNumberFilter<T extends num>(T? min, T? max) {
    return [
      if (min != null) '>=$min',
      if (max != null) '<=$max',
    ];
  }

  static Map<String, dynamic> buildBangumiSearchParams(
    String keyword, {
    List<String> tags = const [],
    String sort = 'heat',
    SearchDateRange? dateRange,
    SearchIntRange? rankRange,
    SearchDoubleRange? scoreRange,
    List<int> weekdays = const [],
  }) {
    final rankFilter = rankRange?.isValid == true
        ? _buildNumberFilter<int>(rankRange!.min, rankRange.max)
        : (sort == 'rank')
            ? [">0", "<=99999"]
            : [">=0", "<=99999"];

    final filter = <String, dynamic>{
      "type": [2],
      "tag": tags,
      "rank": rankFilter,
      "nsfw": false
    };

    if (dateRange?.isValid == true) {
      filter["air_date"] = [">=${dateRange!.start}", "<${dateRange.end}"];
    }
    if (scoreRange?.isValid == true) {
      filter["rating"] =
          _buildNumberFilter<double>(scoreRange!.min, scoreRange.max);
    }
    if (weekdays.isNotEmpty) {
      filter["air_weekday"] = weekdays.toSet().toList()..sort();
    }

    return <String, dynamic>{
      'keyword': keyword,
      'sort': sort,
      "filter": filter,
    };
  }

  static Future<BangumiSearchPage?> bangumiSearch(String keyword,
      {List<String> tags = const [],
      int limit = 20,
      int offset = 0,
      String sort = 'heat',
      SearchDateRange? dateRange,
      SearchIntRange? rankRange,
      SearchDoubleRange? scoreRange,
      List<int> weekdays = const []}) async {
    List<BangumiItem> bangumiList = [];

    final params = buildBangumiSearchParams(
      keyword,
      tags: tags,
      sort: sort,
      dateRange: dateRange,
      rankRange: rankRange,
      scoreRange: scoreRange,
      weekdays: weekdays,
    );

    try {
      final jsonData = await _client.post(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRankSearch,
            [limit, offset]),
        data: params,
      );
      final jsonList = jsonData['data'];
      for (dynamic jsonItem in jsonList) {
        if (jsonItem is Map<String, dynamic>) {
          try {
            BangumiItem bangumiItem = BangumiItem.fromJson(jsonItem);
            if (bangumiItem.nameCn != '') {
              bangumiList.add(bangumiItem);
            }
          } catch (e) {
            KazumiLogger()
                .e('Network: resolve search results failed', error: e);
          }
        }
      }
      return BangumiSearchPage(
        items: bangumiList,
        rawCount: jsonList.length,
      );
    } catch (e) {
      KazumiLogger().e('Network: unknown search problem', error: e);
      return null;
    }
  }

  static Future<BangumiItem?> getBangumiInfoByID(int id) async {
    // 镜像模式优先走 api.qlyyz.top（与官方同构的 /v0/subjects/{id}）；失败回退直连 next.bgm.tv
    if (_proxyEnabled) {
      try {
        final jsonData = await _client.get(ApiEndpoints.bangumiMirrorDomain +
            ApiEndpoints.formatUrl(ApiEndpoints.bangumiInfoByID, [id]));
        return BangumiItem.fromJson(jsonData);
      } catch (e) {
        KazumiLogger().e('Network: mirror bangumi info failed, fallback to direct',
            error: e);
      }
    }
    try {
      final jsonData = await _client.get(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAPINextDomain +
                ApiEndpoints.bangumiInfoByIDNext,
            [id]),
      );
      return BangumiItem.fromJson(jsonData);
    } catch (e) {
      KazumiLogger().e('Network: resolve bangumi item failed', error: e);
      return null;
    }
  }

  /// 获取条目的关联条目（续集/前传/衍生等）。
  ///
  /// 镜像开关开启时优先走 api.qlyyz.top 镜像后端（与官方 api.kazumi.fyi 同一套
  /// Bangumi 原始路径 /v0/subjects/{id}/subjects），失败自动回退直连 api.bgm.tv。
  static Future<List<SubjectRelation>> getRelatedSubjects(int id) async {
    List<SubjectRelation> parse(dynamic jsonData) {
      if (jsonData is! List) return [];
      return jsonData
          .whereType<Map<String, dynamic>>()
          .map(SubjectRelation.fromJson)
          .toList();
    }

    // 镜像模式：优先 api.qlyyz.top
    if (_proxyEnabled) {
      try {
        final jsonData = await _client.get(ApiEndpoints.bangumiMirrorDomain +
            ApiEndpoints.buildBangumiMirrorRelatedPath(id));
        return parse(jsonData);
      } catch (e) {
        KazumiLogger()
            .e('Network: mirror related subjects failed, fallback to direct',
                error: e);
      }
    }

    // 直连 api.bgm.tv
    try {
      final jsonData = await _client.get(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRelatedSubjects,
            [id]),
      );
      return parse(jsonData);
    } catch (e) {
      KazumiLogger().e('Network: resolve related subjects failed', error: e);
      return [];
    }
  }

  static Future<EpisodeInfo> getBangumiEpisodeByID(int id, int episode) async {
    EpisodeInfo episodeInfo = EpisodeInfo.fromTemplate();
    var params = <String, dynamic>{
      'subject_id': id,
      'offset': episode - 1,
      'limit': 1
    };
    try {
      final jsonData = await _client.get(
        ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiEpisodeByID,
        queryParameters: params,
      );
      episodeInfo = EpisodeInfo.fromJson(jsonData['data'][0]);
    } catch (e) {
      KazumiLogger().e('Network: resolve bangumi episode failed', error: e);
    }
    return episodeInfo;
  }

  static Future<List<EpisodeInfo>> getBangumiEpisodesByID(int id) async {
    // 镜像模式优先走 api.qlyyz.top（/v0/episodes 同构）；失败回退直连 api.bgm.tv
    if (_proxyEnabled) {
      try {
        return await _fetchEpisodesPage(ApiEndpoints.bangumiMirrorDomain, id);
      } catch (e) {
        KazumiLogger().e(
            'Network: mirror bangumi episode list failed, fallback to direct',
            error: e);
      }
    }
    return _fetchEpisodesPage(ApiEndpoints.bangumiAPIDomain, id);
  }

  static Future<List<EpisodeInfo>> _fetchEpisodesPage(String base, int id) async {
    final List<EpisodeInfo> episodeList = [];
    const int limit = 100;
    int offset = 0;
    int? total;
    try {
      do {
        final params = <String, dynamic>{
          'subject_id': id,
          'offset': offset,
          'limit': limit,
        };
        final jsonData = await _client.get(
          base + ApiEndpoints.bangumiEpisodeByID,
          queryParameters: params,
        );
        total ??= jsonData['total'] as int?;
        final data = jsonData['data'] as List<dynamic>? ?? [];
        if (data.isEmpty) {
          break;
        }
        episodeList.addAll(data
            .whereType<Map<String, dynamic>>()
            .map((jsonItem) => EpisodeInfo.fromJson(jsonItem)));
        offset += data.length;
      } while (total == null || offset < total);
    } catch (e) {
      KazumiLogger()
          .e('Network: resolve bangumi episode list failed', error: e);
    }
    return episodeList;
  }

  /// 计算连载进度：返回最新已播出的正片集数（0 = 尚未播出）。
  ///
  /// 与 Ani 的 SubjectAiringInfo.computeFromEpisodeList 一致：仅统计正片(type==0)，
  /// 取 airdate <= 今天的最大 sort。
  ///
  /// 修复停播问题：按集顺序检查，如果某集与上一集的间隔超过了
  /// 平均间隔的 2.5 倍，则视为停播（不再往后计数），避免停播后
  /// 仍显示错误的高集数。
  static int computeLatestAiredEpisode(List<EpisodeInfo> episodes) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. 收集正片，按集数排序
    final mains = episodes
        .where((e) => e.type == 0)
        .toList()
      ..sort((a, b) => a.episode.compareTo(b.episode));

    if (mains.isEmpty) return 0;

    // 2. 计算相邻集之间的平均间隔（天）
    int totalGap = 0;
    int gapCount = 0;
    DateTime? prevDate;
    for (final ep in mains) {
      final airdate = ep.airdate.trim();
      if (airdate.isEmpty) continue;
      final d = DateTime.tryParse(airdate);
      if (d == null) continue;
      if (prevDate != null) {
        totalGap += d.difference(prevDate).inDays.abs();
        gapCount++;
      }
      prevDate = d;
    }

    // 如果集数太少（<2 集能算出间隔），回退到简单逻辑
    final avgGap = gapCount > 0 ? totalGap / gapCount : 7.0;

    // 3. 按顺序判定已播出集数
    int latest = 0;
    DateTime? lastAiredDate;
    for (final ep in mains) {
      final epNum = ep.episode.toInt();
      final airdate = ep.airdate.trim();
      if (airdate.isEmpty) break;
      final d = DateTime.tryParse(airdate);
      if (d == null) break;

      // 如果 airdate 是未来，则停止计数
      if (d.isAfter(today)) break;

      // 如果与上一集间隔超过平均间隔的 2 倍（如周更番停播一周），
      // 视为停播：不再往后计数。等真实播出后 airdate 更新、间隔恢复正常，
      // 就会自动重新计入该集。
      if (lastAiredDate != null) {
        final gap = d.difference(lastAiredDate).inDays.abs();
        if (gap > avgGap * 2.0) break; // 停播检测
      }

      latest = epNum;
      lastAiredDate = d;
    }

    return latest;
  }

  static Future<CommentResponse> getBangumiCommentsByID(int id,
      {int offset = 0}) async {
    final url = ApiEndpoints.formatUrl(
        ApiEndpoints.bangumiAPINextDomain +
            ApiEndpoints.bangumiCommentsByIDNext,
        [id, 20, offset]);
    final jsonData = await _proxyGet(url);
    return CommentResponse.fromJson(jsonData);
  }

  static Future<EpisodeCommentResponse> getBangumiCommentsByEpisodeID(
      int id) async {
    final url = ApiEndpoints.formatUrl(
        ApiEndpoints.bangumiAPINextDomain +
            ApiEndpoints.bangumiEpisodeCommentsByIDNext,
        [id]);
    final jsonData = await _proxyGet(url);
    return EpisodeCommentResponse.fromJson(jsonData);
  }

  static Future<CharacterCommentResponse> getCharacterCommentsByCharacterID(
      int id) async {
    final url = ApiEndpoints.formatUrl(
        ApiEndpoints.bangumiAPINextDomain +
            ApiEndpoints.bangumiCharacterCommentsByIDNext,
        [id]);
    final jsonData = await _proxyGet(url);
    return CharacterCommentResponse.fromJson(jsonData);
  }

  static Future<StaffResponse> getBangumiStaffByID(int id) async {
    final jsonData = await _client.get(
      ApiEndpoints.formatUrl(
          ApiEndpoints.bangumiAPINextDomain + ApiEndpoints.bangumiStaffByIDNext,
          [id]),
    );
    return StaffResponse.fromJson(jsonData);
  }

  static Future<CharactersResponse> getCharatersByBangumiID(int id) async {
    final jsonData = await _client.get(
      ApiEndpoints.formatUrl(
          ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiCharacterByID,
          [id]),
    );
    return CharactersResponse.fromJson(jsonData);
  }

  static Future<CharacterFullItem> getCharacterByCharacterID(int id) async {
    CharacterFullItem characterFullItem = CharacterFullItem.fromTemplate();
    try {
      final jsonData = await _client.get(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAPINextDomain +
                ApiEndpoints.bangumiCharacterInfoByCharacterIDNext,
            [id]),
      );
      characterFullItem = CharacterFullItem.fromJson(jsonData);
    } catch (e) {
      KazumiLogger().e('Network: resolve character info failed', error: e);
    }
    return characterFullItem;
  }

  static Future<String?> getUsername() async {
    final user = await getCurrentUser();
    return user?.username;
  }

  static Future<User?> getCurrentUser() async {
    try {
      final jsonData = await _client.get(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAuthAPIMirrorDomain +
                ApiEndpoints.bangumiUsernameByToken,
            []),
        requiresAuth: true,
      );
      if (jsonData['id'] != null) {
        return User.fromJson(Map<String, dynamic>.from(jsonData));
      }
    } on NetworkException catch (e) {
      if (e.statusCode == 401) {
        KazumiLogger().e('Bangumi token unauthorized, please check your token');
        throw StateError('Bangumi token 未授权，请检查您的 token');
      }
      rethrow;
    } catch (e) {
      KazumiLogger().e('Network: get current user failed', error: e);
    }
    return null;
  }

  /// Get the Bangumi collection of the current user
  static Future<List<BangumiCollection>> getBangumiCollectibles({
    List<BangumiCollectionType> includeBangumiTypes = const [
      BangumiCollectionType.planToWatch,
      BangumiCollectionType.watched,
      BangumiCollectionType.watching,
      BangumiCollectionType.onHold,
      BangumiCollectionType.abandoned,
    ],
    String? username,
    required int limit,
    void Function(String message, int current, int total)? onProgress,
  }) async {
    final List<BangumiCollection> bangumiCollection = [];
    final resolvedUsername = username != null && username.isNotEmpty
        ? username
        : await getUsername();
    int failedItemCount = 0;
    int progressCurrent = 0;
    int progressTotal = 0;
    if (resolvedUsername == null) {
      KazumiLogger().w('get username failed');
      return [];
    }

    try {
      const Duration requestInterval = Duration(milliseconds: 250);

      for (final collectionType in includeBangumiTypes) {
        if (collectionType == BangumiCollectionType.unknown) {
          continue;
        }
        int offset = 0;
        int? total;
        bool totalInitialized = false;
        while (true) {
          dynamic jsonData;
          try {
            final url = ApiEndpoints.formatUrl(
                ApiEndpoints.bangumiAuthAPIMirrorDomain +
                    ApiEndpoints.bangumiGetCollection,
                [resolvedUsername, limit, offset, collectionType.value]);
            jsonData = await _client.get(
              url,
              requiresAuth: true,
            );
          } catch (e) {
            KazumiLogger().e(
              'BangumiApi: fetch collection failed. type=${collectionType.value}, offset=$offset',
              error: e,
            );
            rethrow;
          }

          final Map jsonMap = jsonData;
          final List<dynamic> jsonList = jsonMap['data'];
          total ??= jsonMap['total'];
          if (!totalInitialized && total != null) {
            progressTotal += total;
            totalInitialized = true;
          }

          for (dynamic jsonItem in jsonList) {
            if (jsonItem is Map<String, dynamic>) {
              try {
                bangumiCollection.add(BangumiCollection.fromJson(jsonItem));
                progressCurrent++;
                onProgress?.call(
                  '正在拉取${collectionType.label}收藏',
                  progressCurrent,
                  progressTotal,
                );
              } catch (e) {
                KazumiLogger().e(
                  'BangumiApi: parse collection item failed: ${e.toString()}',
                  error: e,
                );
                failedItemCount++;
              }
            }
          }

          if (jsonList.isEmpty || (total != null && offset + limit >= total)) {
            break;
          }

          offset += limit;
          await Future.delayed(requestInterval);
        }
      }
    } catch (e) {
      KazumiLogger().e('Network: get bangumi collection failed', error: e);
      rethrow;
    }
    KazumiLogger()
        .d('get Bangumi collection count: ${bangumiCollection.length}');
    KazumiLogger().d('get item failed count: $failedItemCount');
    return bangumiCollection;
  }

  /// Update the Bangumi collection by ID
  static Future<bool> updateBangumiById(
      int id, Map<String, dynamic> data) async {
    const Duration requestInterval = Duration(milliseconds: 250);
    try {
      await _client.post(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAuthAPIMirrorDomain +
                ApiEndpoints.bangumiSetCollection,
            [id]),
        data: data,
        requiresAuth: true,
      );
      KazumiLogger().d('Update to Bangumi: Id: $id');
      return true;
    } on NetworkException catch (e) {
      String str;
      switch (e.statusCode) {
        case 400:
          str = 'Validation Error 验证错误';
          break;
        case 401:
          str = 'Unauthorized 未经授权';
          break;
        case 404:
          str = 'User not found 用户不存在';
          break;
        default:
          str = 'Error $e';
      }
      KazumiLogger().e('BangumiApi: $str', error: e);
      return false;
    } catch (e) {
      KazumiLogger().e('Network: update bangumi collection failed', error: e);
      rethrow;
    } finally {
      await Future.delayed(requestInterval);
    }
  }

  /// Update the Bangumi collection by Type
  static Future<bool> updateBangumiByType(int id, int localType) async {
    final type = CollectType.fromValue(localType).toBangumiCollectionType();
    if (type == null) {
      return false;
    }
    return await updateBangumiById(id, {'type': type.value});
  }

  /// update or add Bangumi evaluation by subjectID
  static Future<bool> addOrUpdateBangumiEvaluationBySubjectID(
    int subjectID,
    int localType, {
    String? comment,
    int? rate,
    List<String>? tags,
  }) async {
    final bangumiType =
        CollectType.fromValue(localType).toBangumiCollectionType();
    if (bangumiType == null) {
      return false;
    }
    final data = <String, dynamic>{'type': bangumiType.value};
    if (comment != null) data['comment'] = comment;
    if (rate != null) data['rate'] = rate;
    if (tags != null) data['tags'] = tags;
    return updateBangumiById(subjectID, data);
  }
}

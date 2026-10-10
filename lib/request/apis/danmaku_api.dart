import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:yhdm/request/config/api_endpoints.dart';
import 'package:yhdm/request/clients/danmaku_client.dart';
import 'package:yhdm/request/core/dio_factory.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/modules/danmaku/danmaku_module.dart';
import 'package:yhdm/modules/danmaku/danmaku_search_response.dart';
import 'package:yhdm/modules/danmaku/danmaku_episode_response.dart';
import 'package:yhdm/utils/danmaku.dart';
import 'package:yhdm/utils/http_headers.dart';
import 'package:yhdm/utils/string_similarity.dart';

class DanmakuApi {
  static final DanmakuClient _client = DanmakuClient.instance;

  // ============ 弹弹Play API ============

  // 从BgmBangumiID获取DanDanBangumiID
  static Future<int> getDanDanBangumiIDByBgmBangumiID(int bgmBangumiID) async {
    var path = ApiEndpoints.formatUrl(
        ApiEndpoints.dandanAPIInfoByBgmBangumiId, [bgmBangumiID]);
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    DanmakuEpisodeResponse danmakuEpisodeResponse =
        DanmakuEpisodeResponse.fromJson(jsonData);
    return danmakuEpisodeResponse.bangumiId;
  }

  // 从标题获取DanDanBangumiID
  static Future<int> getBangumiIDByTitle(String title) async {
    DanmakuSearchResponse danmakuSearchResponse =
        await getDanmakuSearchResponse(title);

    int bestAnimeId = 0;
    double maxSimilarity = 0;

    for (var anime in danmakuSearchResponse.animes) {
      int animeId = anime.animeId;
      if (animeId >= 100000 || animeId < 2) {
        continue;
      }

      String animeTitle = anime.animeTitle;
      double similarity = calculateSimilarity(animeTitle, title);
      if (similarity == 1) {
        KazumiLogger().i('Danmaku: total match $title');
        return animeId;
      }

      if (similarity > maxSimilarity) {
        maxSimilarity = similarity;
        bestAnimeId = animeId;
        KazumiLogger().i(
            'Danmaku: match anime danmaku $title --- $animeTitle similarity: $similarity');
      }
    }

    return bestAnimeId;
  }

  // 从BangumiID获取分集ID
  static Future<DanmakuEpisodeResponse> getDanmakuEpisodesByBangumiID(
      int bangumiID) async {
    var path = ApiEndpoints.formatUrl(
        ApiEndpoints.dandanAPIInfoByBgmBangumiId, [bangumiID]);
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    DanmakuEpisodeResponse danmakuEpisodeResponse =
        DanmakuEpisodeResponse.fromJson(jsonData);
    return danmakuEpisodeResponse;
  }

  // 从DanDanBangumiID获取分集ID
  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByDanDanBangumiID(
      int bangumiID) async {
    var path = ApiEndpoints.dandanAPIInfo + bangumiID.toString();
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    DanmakuEpisodeResponse danmakuEpisodeResponse =
        DanmakuEpisodeResponse.fromJson(jsonData);
    return danmakuEpisodeResponse;
  }

  // 从标题检索DanDan番剧数据库
  static Future<DanmakuSearchResponse> getDanmakuSearchResponse(
      String title) async {
    var path = ApiEndpoints.dandanAPISearch;
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    Map<String, String> keywordMap = {
      'keyword': title,
    };

    final jsonData = await _client.get(endPoint, queryParameters: keywordMap);
    DanmakuSearchResponse danmakuSearchResponse =
        DanmakuSearchResponse.fromJson(jsonData);
    return danmakuSearchResponse;
  }

  // v2 episode search avoids the anime search's 25-result cap.
  // Fetch full episode lists separately; search results can truncate them.
  static Future<DanmakuSearchResponse> searchAnimes(String title) async {
    final endPoint =
        ApiEndpoints.dandanAPIDomain + ApiEndpoints.dandanAPISearchEpisodes;
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {'anime': title, 'v2': 'true'},
    );
    return DanmakuSearchResponse.fromJson(jsonData);
  }

  static Future<List<DanmakuEntry>> getDanDanmaku(
      int bangumiID, int episode) async {
    List<DanmakuEntry> danmakus = [];
    if (bangumiID == 0) {
      return danmakus;
    }
    var path = ApiEndpoints.dandanAPIComment +
        bangumiID.toString() +
        episode.toString().padLeft(4, '0');
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    Map<String, String> withRelated = {
      'withRelated': 'true',
    };
    KazumiLogger().i("Danmaku: final request URL $endPoint");
    final jsonData = await _client.get(endPoint, queryParameters: withRelated);
    List<dynamic> comments = jsonData['comments'];

    for (var comment in comments) {
      DanmakuEntry danmaku = DanmakuEntry.fromJson(comment);
      // 弹弹play 的 p 字段第 4 段是发送者 hash，不是来源名；统一标记为 Gamer
      // （来源统计 countDanmakuSources 与播放过滤 _isDanmakuSourceEnabled 都按 Gamer 识别）
      danmaku.source = 'Gamer';
      danmakus.add(danmaku);
    }
    return danmakus;
  }

  static Future<List<DanmakuEntry>> getDanDanmakuByEpisodeID(
      int episodeID) async {
    var path = ApiEndpoints.dandanAPIComment + episodeID.toString();
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    List<DanmakuEntry> danmakus = [];
    Map<String, String> withRelated = {
      'withRelated': 'true',
    };
    final jsonData = await _client.get(endPoint, queryParameters: withRelated);
    List<dynamic> comments = jsonData['comments'];

    for (var comment in comments) {
      DanmakuEntry danmaku = DanmakuEntry.fromJson(comment);
      // 弹弹play 的 p 字段第 4 段是发送者 hash，不是来源名；统一标记为 Gamer
      danmaku.source = 'Gamer';
      danmakus.add(danmaku);
    }
    return danmakus;
  }

  // ============ Animeko 弹幕（公益弹幕服务器） ============
  // 协议：GET https://danmaku-cn.myani.org/v1/danmaku/{Bangumi剧集ID}?maxCount=
  // 返回 { danmakuList: [{ id, senderId, danmakuInfo: { playTime(ms), color(int), text, location(TOP/BOTTOM/NORMAL) } }] }
  static const String _animekoCnBase = 'https://danmaku-cn.myani.org';
  static const String _animekoGlobalBase = 'https://danmaku-global.myani.org';
  static const String animekoSource = 'Animeko';

  /// 拉取 Animeko 弹幕（按 Bangumi 剧集 ID），CN 服务器失败自动切 GLOBAL。
  static Future<List<DanmakuEntry>> getAnimekoDanmaku(int episodeId) async {
    if (episodeId <= 0) return const [];
    for (final base in [_animekoCnBase, _animekoGlobalBase]) {
      try {
        final url =
            '$base/v1/danmaku/$episodeId?maxCount=8000&fromTime=0&toTime=-1';
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('User-Agent', getRandomUA());
        request.headers.set('Accept', 'application/json');
        final response = await request.close().timeout(const Duration(seconds: 8));
        final body = await response.transform(utf8.decoder).join();
        client.close();
        final json = jsonDecode(body);
        final list = (json as Map<String, dynamic>)['danmakuList'];
        if (list is! List || list.isEmpty) {
          // 空列表继续试下一个服务器；解析失败也继续
          if (list is List) return const [];
          continue;
        }
        final entries = <DanmakuEntry>[];
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final info = item['danmakuInfo'];
          if (info is! Map<String, dynamic>) continue;
          final text = info['text']?.toString() ?? '';
          if (text.isEmpty) continue;
          final playTimeMs = (info['playTime'] as num?)?.toDouble() ?? 0;
          final colorInt = (info['color'] as num?)?.toInt() ?? -1;
          final location = info['location']?.toString() ?? 'NORMAL';
          // playTime 毫秒 → 秒；TOP/BOTTOM → 顶部/底部弹幕，NORMAL → 滚动
          final type = switch (location) {
            'TOP' => 5,
            'BOTTOM' => 4,
            _ => 1,
          };
          entries.add(DanmakuEntry(
            message: text,
            time: playTimeMs / 1000,
            type: type,
            color: generateDanmakuColor(colorInt),
            source: animekoSource,
          ));
        }
        if (entries.isNotEmpty) {
          KazumiLogger().i('Danmaku: Animeko 拉取到 ${entries.length} 条弹幕');
          return entries;
        }
      } catch (e) {
        KazumiLogger().w('AnimekoDanmaku: 拉取失败($base)', error: e);
      }
    }
    return const [];
  }
}
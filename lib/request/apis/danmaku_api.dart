import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/utils/string_similarity.dart';

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
      danmakus.add(danmaku);
    }
    return danmakus;
  }

  // ============ B站弹幕源 ============

  /// 按番名搜索 B站视频（带重试机制）
  static Future<List<Map<String, dynamic>>> searchBiliVideos(
      String keyword, {
      int maxRetries = 3,
    }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 1) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
        
        final jsonData = await _client.get(
          'https://api.bilibili.com/x/web-interface/search/type',
          queryParameters: {
            'search_type': 'video',
            'keyword': keyword,
          },
        );
        
        if (jsonData is Map<String, dynamic>) {
          final code = jsonData['code'] as int?;
          if (code != 0) {
            KazumiLogger().w('BiliDanmaku: API返回错误码 $code');
            if (code == -412 || code == 412) {
              continue;
            }
            return [];
          }
          
          final result = jsonData['data']?['result'];
          if (result is! List) return [];
          
          final list = <Map<String, dynamic>>[];
          for (final e in result) {
            if (e is! Map) continue;
            final bvid = e['bvid']?.toString() ?? '';
            final aid = (e['aid'] as num?)?.toInt() ?? 0;
            if (bvid.isEmpty && aid == 0) continue;
            final title = (e['title']?.toString() ?? '')
                .replaceAll(RegExp(r'<[^>]+>'), '');
            list.add({
              'bvid': bvid,
              'aid': aid,
              'title': title,
              'duration': e['duration']?.toString() ?? '',
              'author': e['author']?.toString() ?? '',
            });
          }
          return list;
        }
        return [];
      } catch (e) {
        KazumiLogger().w('BiliDanmaku: 搜索失败 (尝试 $attempt/$maxRetries)', error: e);
        if (attempt == maxRetries) return [];
      }
    }
    return [];
  }

  /// 获取 B站视频 cid
  static Future<int> getBiliCid({
    String bvid = '',
    int aid = 0,
    required int episode,
    int maxRetries = 2,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 1) {
          await Future.delayed(Duration(seconds: attempt));
        }
        
        final jsonData = await _client.get(
          'https://api.bilibili.com/x/player/pagelist',
          queryParameters: {
            if (bvid.isNotEmpty) 'bvid': bvid else 'aid': aid,
          },
        );
        
        final pages = (jsonData as Map<String, dynamic>)['data'];
        if (pages is! List || pages.isEmpty || episode < 1 || episode > pages.length) {
          return 0;
        }
        return (pages[episode - 1]['cid'] as num?)?.toInt() ?? 0;
      } catch (e) {
        KazumiLogger().w('BiliDanmaku: 获取cid失败 (尝试 $attempt/$maxRetries)', error: e);
        if (attempt == maxRetries) return 0;
      }
    }
    return 0;
  }

  /// 拉取 B站弹幕
  static Future<List<DanmakuEntry>> getBiliDanmaku(int cid) async {
    if (cid <= 0) return [];
    
    try {
      final response = await Dio().get(
        'https://api.bilibili.com/x/v1/dm/list.so',
        queryParameters: {'oid': cid},
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': getRandomUA(),
            'Referer': 'https://www.bilibili.com',
            'Origin': 'https://www.bilibili.com',
          },
        ),
      );
      
      final xml = response.data?.toString() ?? '';
      if (xml.isEmpty) return [];
      
      return _parseBiliXml(xml);
    } catch (e) {
      KazumiLogger().e('BiliDanmaku: 拉取弹幕失败', error: e);
      return [];
    }
  }

  /// 解析 B站弹幕 XML
  static List<DanmakuEntry> _parseBiliXml(String xml) {
    final entries = <DanmakuEntry>[];
    final regex = RegExp(r'<d p="([^"]+)">([^<]*)</d>');
    
    for (final m in regex.allMatches(xml)) {
      final attrs = m.group(1)?.split(',') ?? const [];
      if (attrs.isEmpty) continue;
      
      final time = double.tryParse(attrs[0]) ?? 0;
      final type = attrs.length > 1 ? int.tryParse(attrs[1]) ?? 1 : 1;
      final colorValue = attrs.length > 3 ? int.tryParse(attrs[3]) ?? 0xFFFFFF : 0xFFFFFF;
      final message = m.group(2) ?? '';
      if (message.isEmpty) continue;
      
      entries.add(DanmakuEntry(
        message: message,
        time: time,
        type: type,
        color: Color(0xFF000000 | colorValue),
        source: 'BiliBili',
      ));
    }
    return entries;
  }

  // ============================================================
  // ============ 🔥 核心：同时拉取多个来源的弹幕 ============
  // ============================================================

  /// 同时从多个来源拉取弹幕（并发请求）
  /// 返回 Map<来源, 弹幕列表>
  static Future<Map<String, List<DanmakuEntry>>> getDanmakuFromAllSources({
    required String keyword,
    required int episode,
    int bangumiID = 0,  // 弹弹Play的番剧ID（可选）
  }) async {
    final results = <String, List<DanmakuEntry>>{};
    
    // 创建多个并发任务
    final futures = <Future>[];
    final sourceNames = <String>[];
    
    // 1. 弹弹Play来源（如果有bangumiID）
    if (bangumiID > 0) {
      futures.add(_fetchDandanDanmaku(bangumiID, episode));
      sourceNames.add('dandanplay');
    } else {
      // 如果没有bangumiID，先搜索获取
      futures.add(_fetchDandanDanmakuBySearch(keyword, episode));
      sourceNames.add('dandanplay');
    }
    
    // 2. B站来源
    futures.add(_fetchBiliDanmaku(keyword, episode));
    sourceNames.add('bilibili');
    
    // 3. 可以继续添加更多来源（如：AcFun、Tucao等）
    // futures.add(_fetchAcfunDanmaku(keyword, episode));
    // sourceNames.add('acfun');
    
    // 等待所有请求完成（任何一个失败不影响其他）
    final responses = await Future.wait(futures, eagerError: false);
    
    // 组装结果
    for (int i = 0; i < responses.length; i++) {
      final source = sourceNames[i];
      final danmakus = responses[i] as List<DanmakuEntry>;
      results[source] = danmakus;
      KazumiLogger().i('Danmaku: 从 $source 获取到 ${danmakus.length} 条弹幕');
    }
    
    return results;
  }

  /// 从弹弹Play获取弹幕（通过bangumiID）
  static Future<List<DanmakuEntry>> _fetchDandanDanmaku(
      int bangumiID, int episode) async {
    try {
      return await getDanDanmaku(bangumiID, episode);
    } catch (e) {
      KazumiLogger().w('弹弹Play弹幕获取失败', error: e);
      return [];
    }
  }

  /// 从弹弹Play获取弹幕（通过搜索）
  static Future<List<DanmakuEntry>> _fetchDandanDanmakuBySearch(
      String keyword, int episode) async {
    try {
      // 先搜索获取bangumiID
      final bangumiID = await getBangumiIDByTitle(keyword);
      if (bangumiID > 0) {
        return await getDanDanmaku(bangumiID, episode);
      }
      return [];
    } catch (e) {
      KazumiLogger().w('弹弹Play搜索获取弹幕失败', error: e);
      return [];
    }
  }

  /// 从B站获取弹幕
  static Future<List<DanmakuEntry>> _fetchBiliDanmaku(
      String keyword, int episode) async {
    try {
      // 搜索视频
      final videos = await searchBiliVideos(keyword);
      if (videos.isEmpty) return [];
      
      // 取第一个结果
      final firstVideo = videos.first;
      final bvid = firstVideo['bvid'] as String? ?? '';
      final aid = firstVideo['aid'] as int? ?? 0;
      
      // 获取cid
      final cid = await getBiliCid(
        bvid: bvid,
        aid: aid,
        episode: episode,
      );
      if (cid == 0) return [];
      
      // 获取弹幕
      return await getBiliDanmaku(cid);
    } catch (e) {
      KazumiLogger().w('B站弹幕获取失败', error: e);
      return [];
    }
  }

  // ============================================================
  // ============ 🎯 合并和去重弹幕 ============
  // ============================================================

  /// 合并多个来源的弹幕，并按时间排序
  static List<DanmakuEntry> mergeDanmakuFromSources(
      Map<String, List<DanmakuEntry>> sourceMap) {
    final allDanmakus = <DanmakuEntry>[];
    
    // 合并所有弹幕
    for (final entry in sourceMap.entries) {
      final source = entry.key;
      final danmakus = entry.value;
      
      // 为每个弹幕标记来源
      for (var dm in danmakus) {
        // 如果弹幕没有source字段，添加来源标识
        if (dm.source.isEmpty) {
          dm = dm.copyWith(source: source);
        }
        allDanmakus.add(dm);
      }
    }
    
    // 按时间排序
    allDanmakus.sort((a, b) => a.time.compareTo(b.time));
    
    // 去重（相同时间+相同内容的弹幕只保留一个）
    final uniqueDanmakus = <DanmakuEntry>[];
    final seen = <String>{};
    
    for (final dm in allDanmakus) {
      final key = '${dm.time.toStringAsFixed(2)}_${dm.message}';
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueDanmakus.add(dm);
      }
    }
    
    KazumiLogger().i('Danmaku: 合并后共 ${uniqueDanmakus.length} 条弹幕（原始 ${allDanmakus.length} 条）');
    return uniqueDanmakus;
  }

  /// 一站式获取并合并所有来源的弹幕
  static Future<List<DanmakuEntry>> getMergedDanmaku({
    required String keyword,
    required int episode,
    int bangumiID = 0,
  }) async {
    // 1. 同时从所有来源拉取
    final sourceMap = await getDanmakuFromAllSources(
      keyword: keyword,
      episode: episode,
      bangumiID: bangumiID,
    );
    
    // 2. 合并去重
    return mergeDanmakuFromSources(sourceMap);
  }

  // ============================================================
  // ============ 📊 统计信息 ============
  // ============================================================

  /// 获取各来源弹幕统计
  static Future<Map<String, int>> getDanmakuStatistics({
    required String keyword,
    required int episode,
    int bangumiID = 0,
  }) async {
    final sourceMap = await getDanmakuFromAllSources(
      keyword: keyword,
      episode: episode,
      bangumiID: bangumiID,
    );
    
    final stats = <String, int>{};
    for (final entry in sourceMap.entries) {
      stats[entry.key] = entry.value.length;
    }
    return stats;
  }
}
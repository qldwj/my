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

  // ============ B站弹幕源 ============

  /// 众包共享后端：按 Bangumi ID + 集数查询 B站 cid（自己的 PHP）
  static const String _biliCidApi = 'https://qlyyz.xyz/api/v0/danmaku_bili.php';

  /// 查询 cid 映射（找不到返回 0）
  static Future<int> queryBiliCidFromServer(int bangumiId, int episode) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final url = '$_biliCidApi?action=query&bangumi_id=$bangumiId&episode=$episode';
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', getRandomUA());
      final response = await request.close().timeout(const Duration(seconds: 6));
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body);
      if (json is Map && json['found'] == true) {
        return (json['cid'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      KazumiLogger().w('BiliDanmaku: 查询 cid 映射失败', error: e);
    }
    return 0;
  }

  /// 上传 cid 映射（用户手动搜索匹配后）
  static Future<bool> uploadBiliCidToServer(
    int bangumiId,
    int episode,
    int cid, {
    int epId = 0,
    String title = '',
  }) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final request =
          await client.postUrl(Uri.parse('$_biliCidApi?action=upload'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('User-Agent', getRandomUA());
      request.add(utf8.encode(jsonEncode({
        'bangumi_id': bangumiId,
        'episode': episode,
        'cid': cid,
        'ep_id': epId,
        'title': title,
      })));
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body);
      return json is Map && json['success'] == true;
    } catch (e) {
      KazumiLogger().w('BiliDanmaku: 上传 cid 映射失败', error: e);
      return false;
    }
  }

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

  /// 拉取 B站弹幕（优先 protobuf seg.so 分段，XML 兜底）
  /// [cid] 视频 cid；分段按 6 分钟/段，拉满全片
  static Future<List<DanmakuEntry>> getBiliDanmaku(int cid) async {
    if (cid <= 0) return [];
    final entries = <DanmakuEntry>[];
    // protobuf 分段拉取（每段 6 分钟，最多 20 段兜底）
    for (int seg = 1; seg <= 20; seg++) {
      final batch = await _getBiliSeg(cid, seg);
      if (batch.isEmpty) break; // 该段无弹幕 = 到末尾
      entries.addAll(batch);
      if (batch.length < 6000) break; // 不满段 = 最后一段
    }
    if (entries.isNotEmpty) {
      return entries;
    }
    // 旧 XML 兜底（deflate 解压）
    return _getBiliXml(cid);
  }

  /// 拉取 B站弹幕分段（protobuf，content 字段=7）
  static Future<List<DanmakuEntry>> _getBiliSeg(int cid, int segmentIndex) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final url =
          'https://api.bilibili.com/x/v2/dm/list/seg.so?type=1&oid=$cid&segment_index=$segmentIndex';
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', getRandomUA());
      request.headers.set('Referer', 'https://www.bilibili.com');
      final response = await request.close().timeout(const Duration(seconds: 8));
      final bytes = await response.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      client.close();
      if (bytes.isEmpty) return const [];
      return _parseBiliProto(bytes);
    } catch (e) {
      KazumiLogger().w('BiliDanmaku: seg.so 分段 $segmentIndex 失败', error: e);
      return const [];
    }
  }

  /// 解析 B站弹幕 protobuf（DmSegMobileReply.elems → DanmakuElem）
  /// 字段：1=id(int64) 2=progress(ms,int32) 3=mode 5=color 6=midHash 7=content(string)
  static List<DanmakuEntry> _parseBiliProto(List<int> bytes) {
    final entries = <DanmakuEntry>[];
    var i = 0;
    // 顶层字段：elems 是 field 1, wire type 2 (length-delimited)
    while (i < bytes.length) {
      final tagResult = _readVarint(bytes, i);
      if (tagResult == null) break;
      final (tag, ni) = tagResult;
      i = ni;
      final field = tag >> 3;
      final wire = tag & 7;
      if (field == 1 && wire == 2) {
        final lenResult = _readVarint(bytes, i);
        if (lenResult == null) break;
        final (len, ni2) = lenResult;
        i = ni2;
        final elemEnd = i + len;
        final entry = _parseProtoElem(bytes, i, elemEnd);
        if (entry != null) entries.add(entry);
        i = elemEnd;
      } else {
        // 跳过未知字段
        final skip = _skipField(bytes, i, wire);
        if (skip == null) break;
        i = skip;
      }
    }
    return entries;
  }

  /// 解析单条 DanmakuElem
  static DanmakuEntry? _parseProtoElem(List<int> bytes, int start, int end) {
    var progressMs = 0;
    var mode = 1;
    var colorInt = 0xFFFFFF;
    String content = '';
    var i = start;
    while (i < end) {
      final tagResult = _readVarint(bytes, i);
      if (tagResult == null) break;
      final (tag, ni) = tagResult;
      i = ni;
      final field = tag >> 3;
      final wire = tag & 7;
      if (wire == 0) {
        final v = _readVarint(bytes, i);
        if (v == null) break;
        final (value, ni2) = v;
        i = ni2;
        if (field == 2) progressMs = value.toInt();
        if (field == 3) mode = value.toInt();
      } else if (wire == 2) {
        final lenResult = _readVarint(bytes, i);
        if (lenResult == null) break;
        final (len, ni2) = lenResult;
        i = ni2;
        final strBytes = bytes.sublist(i, i + len);
        i += len;
        if (field == 7) {
          content = utf8.decode(strBytes, allowMalformed: true);
        }
      } else if (wire == 5) {
        if (i + 4 > end) break;
        if (field == 5) {
          colorInt = bytes[i] |
              (bytes[i + 1] << 8) |
              (bytes[i + 2] << 16) |
              (bytes[i + 3] << 24);
        }
        i += 4;
      } else {
        // 其它 wire：尝试跳过
        final skip = _skipField(bytes, i, wire);
        if (skip == null) break;
        i = skip;
      }
    }
    if (content.isEmpty) return null;
    // progress 毫秒→秒；mode 4/5 映射底部/顶部
    final type = mode == 4 ? 4 : (mode == 5 ? 5 : 1);
    return DanmakuEntry(
      message: content,
      time: progressMs / 1000.0,
      type: type,
      color: Color(0xFF000000 | colorInt),
      source: 'BiliBili',
    );
  }

  static (int, int)? _readVarint(List<int> bytes, int i) {
    var result = 0;
    var shift = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      i++;
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) return (result, i);
      shift += 7;
      if (shift >= 70) return null;
    }
    return null;
  }

  static int? _skipField(List<int> bytes, int i, int wire) {
    switch (wire) {
      case 0:
        final v = _readVarint(bytes, i);
        return v?.$2;
      case 1:
        return i + 8 <= bytes.length ? i + 8 : null;
      case 2:
        final v = _readVarint(bytes, i);
        if (v == null) return null;
        return i + v.$1 <= bytes.length ? i + v.$1 : null;
      case 5:
        return i + 4 <= bytes.length ? i + 4 : null;
      default:
        return null;
    }
  }

  /// 拉取 B站弹幕 XML（deflate 解压）
  static Future<List<DanmakuEntry>> _getBiliXml(int cid) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final request = await client
          .getUrl(Uri.parse('https://comment.bilibili.com/$cid.xml'));
      request.headers.set('User-Agent', getRandomUA());
      request.headers.set('Referer', 'https://www.bilibili.com');
      final response = await request.close().timeout(const Duration(seconds: 8));
      final bytes = await response.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      client.close();
      if (bytes.isEmpty) return const [];
      // deflate 解压（zlib raw）
      final decoded = ZLibDecoder(raw: true).convert(bytes);
      final xml = utf8.decode(decoded, allowMalformed: true);
      return _parseBiliXml(xml);
    } catch (e) {
      KazumiLogger().w('BiliDanmaku: XML 拉取失败', error: e);
      return const [];
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
    // 合并所有弹幕
for (final entry in sourceMap.entries) {
  final source = entry.key;
  final danmakus = entry.value;
  
  // 为每个弹幕标记来源
  for (var dm in danmakus) {
    // 如果弹幕没有source字段，添加来源标识
    if (dm.source.isEmpty) {
      // ✅ 直接设置 source 属性（如果 DanmakuEntry 有 source 字段）
      dm.source = source;
      // 或者如果 source 是 final 的，创建新对象：
      // dm = DanmakuEntry(
      //   message: dm.message,
      //   time: dm.time,
      //   type: dm.type,
      //   color: dm.color,
      //   source: source,
      // );
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
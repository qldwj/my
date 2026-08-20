import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

String decodeVideoSource(String iframeUrl) {
  final decodedUrl = Uri.decodeFull(iframeUrl);
  final regExp = RegExp(
    r'(http[s]?://.*?\.m3u8)|(http[s]?://.*?\.mp4)',
    caseSensitive: false,
  );

  final uri = Uri.parse(decodedUrl);
  final params = uri.queryParameters;

  var matchedUrl = iframeUrl;
  params.forEach((key, value) {
    if (regExp.hasMatch(value)) {
      matchedUrl = value;
      return;
    }
  });

  return Uri.encodeFull(matchedUrl);
}

int extractEpisodeNumber(String input) {
  final regExp = RegExp(r'第?(\d+)[话集]?');
  final match = regExp.firstMatch(input);

  if (match != null && match.group(1) != null) {
    return int.tryParse(match.group(1)!) ?? 0;
  }

  return 0;
}

Future<String> getPlayerTempPath() async {
  final directory = await getTemporaryDirectory();
  return directory.path;
}

String buildShadersAbsolutePath(String baseDirectory, List<String> shaders) {
  final absolutePaths = shaders.map((shader) {
    return path.join(baseDirectory, shader);
  }).toList();
  if (Platform.isWindows) {
    return absolutePaths.join(';');
  }
  return absolutePaths.join(':');
}

/// 标准视频扩展名集合（这些后缀的 URL 无需嗅探，直接交给播放器）

/// 标准视频扩展名（这些后缀的 URL 无需嗅探，直接交给播放器）。
/// 非标准后缀（如 .webp/.png 伪装成 HLS 的流）才需要嗅探。
const List<String> kStandardVideoExtensions = [
  '.mp4', '.m3u8', '.flv', '.mkv', '.webm', '.ts',
  '.mpd', '.m4s', '.m4v', '.mov', '.avi', '.wmv',
];

/// 判断 URL 路径是否以标准视频扩展名结尾（忽略 query/fragment）。
bool isStandardVideoUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final p = uri.path.toLowerCase();
    return kStandardVideoExtensions.any(p.endsWith);
  } catch (_) {
    return false;
  }
}

/// 快速嗅探 URL 是否为 HLS 伪装流（.webp/.png 后缀返回 #EXTM3U）。
///
/// 优化点（对比旧版）：使用 dart:io HttpClient 流式读取**前 1KB** 即断开，
/// 无论服务器是否响应 Range，都不会下载整个响应体；
/// 超时 1 秒，失败/超时立即返回 auto，绝不阻塞播放。
Future<VideoSourceFormat> sniffHlsFormat(
  String url, {
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 1),
}) async {
  final cacheKey = _sniffCacheKey(url);
  final cached = _sniffCacheGet(cacheKey);
  if (cached != null) return cached;

  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = timeout;
    final req = await client
        .getUrl(Uri.parse(url))
        .timeout(timeout);
    req.headers.set('User-Agent',
        headers?['user-agent'] ?? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
    if (headers != null) {
      headers.forEach((k, v) {
        if (k.toLowerCase() != 'user-agent' && v.isNotEmpty) {
          req.headers.set(k, v);
        }
      });
    }
    // 请求 Range，服务器遵守则只回 1KB；不遵守也无所谓，我们只读 1KB 就关
    req.headers.set('Range', 'bytes=0-1023');
    final resp = await req.close().timeout(timeout);
    // 流式只取前 1KB，随后立即关闭连接，不等待全量下载
    final body = <int>[];
    await for (final chunk in resp.timeout(timeout)) {
      body.addAll(chunk);
      if (body.length >= 1024) break;
    }
    final text = utf8.decode(body.take(1024).toList(), allowMalformed: true);
    final trimmed = text.trimLeft();
    final result = (trimmed.startsWith('#EXTM3U') || trimmed.startsWith('#EXT-X-'))
        ? VideoSourceFormat.hls
        : VideoSourceFormat.auto;
    _sniffCachePut(cacheKey, result);
    return result;
  } catch (_) {
    // 任何异常/超时都视为无法确认，返回 auto 交给播放器默认处理
  } finally {
    try {
      client?.close(force: true);
    } catch (_) {}
  }
  return VideoSourceFormat.auto;
}

/// ─── 嗅探结果缓存（优化2）──────────────────────────────
/// 同一来源（host+path）的伪装流嗅探结果缓存 5 分钟，
/// 重复播放/切集时直接命中，0 等待。
const Duration _sniffCacheTtl = Duration(minutes: 5);
const int _sniffCacheMax = 100;
final Map<String, VideoSourceFormat> _sniffCache = {};
final Map<String, DateTime> _sniffCacheAt = {};

String _sniffCacheKey(String url) {
  try {
    final uri = Uri.parse(url);
    return '${uri.host}${uri.path}';
  } catch (_) {
    return url;
  }
}

VideoSourceFormat? _sniffCacheGet(String key) {
  final cached = _sniffCache[key];
  if (cached == null) return null;
  final at = _sniffCacheAt[key];
  if (at == null) {
    _sniffCache.remove(key);
    return null;
  }
  if (DateTime.now().difference(at) > _sniffCacheTtl) {
    _sniffCache.remove(key);
    _sniffCacheAt.remove(key);
    return null;
  }
  return cached;
}

void _sniffCachePut(String key, VideoSourceFormat value) {
  if (_sniffCache.length >= _sniffCacheMax) {
    _sniffCache.clear();
    _sniffCacheAt.clear();
  }
  _sniffCache[key] = value;
  _sniffCacheAt[key] = DateTime.now();
}

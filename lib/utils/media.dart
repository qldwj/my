import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
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
const List<String> kStandardVideoExtensions = [
  '.mp4', '.m3u8', '.flv', '.mkv', '.webm', '.ts',
  '.mpd', '.m4s', '.m4v', '.mov', '.avi', '.wmv',
];

/// 判断 URL 路径（去掉 query/fragment）是否以标准视频扩展名结尾。
///
/// 用于决定是否需要内容嗅探：标准视频后缀直接播放；
/// 非标准后缀（如 .webp/.png 伪装的 HLS 流）需要嗅探确认格式。
bool isStandardVideoUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final p = uri.path.toLowerCase();
    return kStandardVideoExtensions.any(p.endsWith);
  } catch (_) {
    return false;
  }
}

/// 嗅探 URL 是否为 HLS 流（非标准后缀的伪装视频流）。
///
/// 部分视频源用 .webp/.png 等伪装后缀返回真正的 HLS 播放列表
/// （内容以 #EXTM3U 开头）。此函数请求内容前若干字节，
/// 命中即返回 [VideoSourceFormat.hls]，否则返回 auto。
/// 超时/失败返回 auto，绝不阻塞播放。
Future<VideoSourceFormat> sniffHlsFormat(
  String url, {
  Map<String, String>? headers,
}) async {
  try {
    final resp = await http
        .get(Uri.parse(url), headers: headers ?? const {})
        .timeout(const Duration(seconds: 4));
    if (resp.statusCode != 200) return VideoSourceFormat.auto;
    final head = resp.bodyBytes.take(256).toList();
    final text = utf8.decode(head, allowMalformed: true).trim();
    if (text.startsWith('#EXTM3U') || text.startsWith('#EXT-X-')) {
      return VideoSourceFormat.hls;
    }
  } catch (_) {}
  return VideoSourceFormat.auto;
}

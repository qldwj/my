import 'dart:io';
import 'package:kazumi/services/logging/logger.dart';
import 'package:http/http.dart' as http;

/// 视频源测速结果
class SourceSpeedResult {
  final String sourceName;
  final String sourceUrl;
  final int latencyMs;
  final bool isAvailable;
  final bool needsVerification;

  const SourceSpeedResult({
    required this.sourceName,
    required this.sourceUrl,
    required this.latencyMs,
    required this.isAvailable,
    this.needsVerification = false,
  });
}

/// 视频源智能测速工具
///
/// 在点击播放时调用，对所有可用源进行测速，
/// 按速度排序（最快的排最前），
/// 需要验证/不可用的排最后。
class SpeedTester {
  static final SpeedTester _instance = SpeedTester._internal();
  factory SpeedTester() => _instance;
  SpeedTester._internal();

  /// 测速缓存（内存），key = sourceUrl
  final Map<String, _CachedResult> _cache = {};

  /// 缓存有效期 30 分钟
  static const int _cacheTtlMs = 30 * 60 * 1000;

  /// 对多个源进行测速，返回排序后的结果
  ///
  /// [sources] 格式: [{name: '源A', url: 'https://...'}, ...]
  Future<List<SourceSpeedResult>> testSources(
    List<Map<String, String>> sources,
  ) async {
    final results = <SourceSpeedResult>[];

    // 并行测速所有源
    final futures = sources.map((source) => _testSingleSource(source));
    final tested = await Future.wait(futures);

    for (final result in tested) {
      results.add(result);
    }

    // 排序：可用最快的排最前，不可用/需验证排最后
    results.sort((a, b) {
      // 不可用排最后
      if (a.isAvailable != b.isAvailable) {
        return a.isAvailable ? -1 : 1;
      }
      // 需要验证排在可用之后、不可用之前
      if (a.needsVerification != b.needsVerification) {
        return a.needsVerification ? 1 : -1;
      }
      // 按延迟从小到大
      return a.latencyMs.compareTo(b.latencyMs);
    });

    return results;
  }

  Future<SourceSpeedResult> _testSingleSource(
    Map<String, String> source,
  ) async {
    final url = source['url'] ?? '';
    final name = source['name'] ?? '未知源';

    // 检查缓存
    final cached = _cache[url];
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - cached.timestampMs <
            _cacheTtlMs) {
      return cached.result;
    }

    try {
      final stopwatch = Stopwatch()..start();
      final response = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      stopwatch.stop();

      final isAvailable = response.statusCode == 200;
      final needsVerification = response.statusCode == 302 ||
          response.statusCode == 403 ||
          response.statusCode == 401;

      final result = SourceSpeedResult(
        sourceName: name,
        sourceUrl: url,
        latencyMs: stopwatch.elapsedMilliseconds,
        isAvailable: isAvailable,
        needsVerification: needsVerification || !isAvailable,
      );

      // 写入缓存
      _cache[url] = _CachedResult(
        result: result,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

      return result;
    } catch (e) {
      KazumiLogger().w('SpeedTester: 测速失败 $name', error: e);
      return SourceSpeedResult(
        sourceName: name,
        sourceUrl: url,
        latencyMs: -1,
        isAvailable: false,
        needsVerification: false,
      );
    }
  }

  /// 清空缓存
  void clearCache() => _cache.clear();
}

class _CachedResult {
  final SourceSpeedResult result;
  final int timestampMs;

  const _CachedResult({
    required this.result,
    required this.timestampMs,
  });
}

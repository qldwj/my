import 'dart:io';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:http/http.dart' as http;

/// 视频源测速结果
class SourceSpeedResult {
  final int roadIndex;
  final String roadName;
  final String testUrl;
  final int latencyMs;
  final bool isAvailable;

  const SourceSpeedResult({
    required this.roadIndex,
    required this.roadName,
    required this.testUrl,
    required this.latencyMs,
    required this.isAvailable,
  });
}

/// 视频源智能测速工具
///
/// 在获取到剧集线路后，对所有线路进行测速，
/// 按速度排序（最快的排最前），不可用的排最后。
class SpeedTester {
  static final SpeedTester _instance = SpeedTester._internal();
  factory SpeedTester() => _instance;
  SpeedTester._internal();

  /// 对多个 Road 进行测速，返回排序后的结果
  ///
  /// [roads] 从 plugin.queryChapterRoads() 获取的线路列表
  /// 返回按速度排序后的 roads
  static Future<List<Road>> testAndSortRoads(List<Road> roads) async {
    if (roads.isEmpty) return roads;

    final results = <SourceSpeedResult>[];
    final urls = <String>[];

    // 收集所有可测试的 URL
    for (int i = 0; i < roads.length; i++) {
      final road = roads[i];
      // 取 road.data 中第一个有效 URL 作为测速目标
      final testUrl = road.data.isNotEmpty ? road.data.first : '';
      urls.add(testUrl);
    }

    // 并行测速
    final futures = <Future<SourceSpeedResult>>[];
    for (int i = 0; i < roads.length; i++) {
      futures.add(_testRoad(i, roads[i].name, urls[i]));
    }
    final tested = await Future.wait(futures);
    results.addAll(tested);

    // 按速度排序（可用+延迟低的在前）
    final sortedIndices = List.generate(roads.length, (i) => i);
    sortedIndices.sort((a, b) {
      final ra = results[a];
      final rb = results[b];
      // 可用排前面
      if (ra.isAvailable != rb.isAvailable) {
        return ra.isAvailable ? -1 : 1;
      }
      // 按延迟从小到大
      return ra.latencyMs.compareTo(rb.latencyMs);
    });

    // 返回排序后的 roads
    return sortedIndices.map((i) => roads[i]).toList();
  }

  static Future<SourceSpeedResult> _testRoad(
    int index,
    String name,
    String url,
  ) async {
    if (url.isEmpty) {
      return SourceSpeedResult(
        roadIndex: index,
        roadName: name,
        testUrl: url,
        latencyMs: -1,
        isAvailable: false,
      );
    }

    try {
      final stopwatch = Stopwatch()..start();
      final response = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      stopwatch.stop();

      return SourceSpeedResult(
        roadIndex: index,
        roadName: name,
        testUrl: url,
        latencyMs: stopwatch.elapsedMilliseconds,
        isAvailable: response.statusCode == 200,
      );
    } catch (e) {
      KazumiLogger().w('SpeedTester: 测速失败 $name', error: e);
      return SourceSpeedResult(
        roadIndex: index,
        roadName: name,
        testUrl: url,
        latencyMs: -1,
        isAvailable: false,
      );
    }
  }

  /// 获取结果中可用线路的数量
  static int countAvailable(List<SourceSpeedResult> results) {
    return results.where((r) => r.isAvailable).length;
  }
}

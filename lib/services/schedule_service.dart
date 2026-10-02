import 'dart:convert';
import 'dart:io';

/// 🆕 放送时刻服务（对接服务端 schedule.php，Animeko 式精确时间）
class WeeklyAiring {
  final int dayOfWeek; // 1-7 周一=1
  final String time; // "22:00"（显示时区）
  WeeklyAiring({required this.dayOfWeek, required this.time});
}

class ScheduleService {
  ScheduleService._();

  static const String _api = 'https://qlyyz.xyz/api/v0/schedule.php';

  /// 批量查询收藏番的放送规律（周几 + 时刻），tz 为显示时区（默认 +8 北京）
  static Future<Map<int, WeeklyAiring>> fetchWeekly(
    List<int> ids, {
    int tz = 8,
  }) async {
    final result = <int, WeeklyAiring>{};
    final uniq = ids.toSet().toList();
    // 每批并发 6 个，避免打爆服务端
    for (var i = 0; i < uniq.length; i += 6) {
      final batch = uniq.sublist(i, (i + 6).clamp(0, uniq.length));
      final futures = batch.map((id) => _fetchOne(id, tz: tz));
      final list = await Future.wait(futures);
      for (final r in list) {
        if (r != null) result[r.$1] = r.$2;
      }
    }
    return result;
  }

  static Future<(int, WeeklyAiring)?> _fetchOne(int id, {int tz = 8}) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(
        Uri.parse('$_api?action=weekly&id=$id&tz=$tz'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body);
      if (data is Map &&
          data['success'] == true &&
          data['dayOfWeek'] is int &&
          data['time'] is String) {
        return (
          id,
          WeeklyAiring(
            dayOfWeek: data['dayOfWeek'] as int,
            time: data['time'] as String,
          ),
        );
      }
    } catch (_) {}
    return null;
  }
}

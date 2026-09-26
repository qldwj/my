import 'dart:convert';

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 播放崩溃自动恢复
///
/// 原理：
///   播放中每隔几秒把「番剧 id + 集数 + 播放位置 + 时间戳」写入本地。
///   正常退出播放页时清除记录。
///   下次启动 App 时如果发现残留记录（说明上次异常退出/崩溃），
///   提示用户「继续观看《XX》第 N 集」。
class PlaybackRecoveryService {
  PlaybackRecoveryService._();

  /// 写入恢复点（播放中定期调用）
  static Future<void> save({
    required int bangumiId,
    required String bangumiName,
    required int episode,
    required int positionMs,
    required int durationMs,
  }) async {
    if (bangumiId <= 0 || episode <= 0) return;
    // 播放刚开始（<10 秒）或已接近结尾（<30 秒）不记，避免无意义恢复
    if (positionMs < 10000) return;
    if (durationMs > 0 && durationMs - positionMs < 30000) return;
    try {
      await GStorage.putSetting(
        SettingsKeys.playbackRecoveryPoint,
        jsonEncode({
          'id': bangumiId,
          'name': bangumiName,
          'ep': episode,
          'pos': positionMs,
          'ts': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      KazumiLogger().w('PlaybackRecovery: 保存失败', error: e);
    }
  }

  /// 正常退出播放页时清除
  static Future<void> clear() async {
    await GStorage.putSetting(SettingsKeys.playbackRecoveryPoint, '');
  }

  /// 读取恢复点；超过 24 小时或无效则返回 null
  static PlaybackRecoveryPoint? read() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.playbackRecoveryPoint);
      if (raw.isEmpty) return null;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      final ts = (d['ts'] as num?)?.toInt() ?? 0;
      // 超过 24 小时视为过期
      if (DateTime.now().millisecondsSinceEpoch - ts > 24 * 3600 * 1000) {
        return null;
      }
      final id = (d['id'] as num?)?.toInt() ?? 0;
      final ep = (d['ep'] as num?)?.toInt() ?? 0;
      if (id <= 0 || ep <= 0) return null;
      return PlaybackRecoveryPoint(
        bangumiId: id,
        bangumiName: d['name']?.toString() ?? '',
        episode: ep,
        positionMs: (d['pos'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      KazumiLogger().w('PlaybackRecovery: 读取失败', error: e);
      return null;
    }
  }
}

class PlaybackRecoveryPoint {
  const PlaybackRecoveryPoint({
    required this.bangumiId,
    required this.bangumiName,
    required this.episode,
    required this.positionMs,
  });

  final int bangumiId;
  final String bangumiName;
  final int episode;
  final int positionMs;

  String get positionText {
    final d = Duration(milliseconds: positionMs);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

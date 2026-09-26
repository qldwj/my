import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 自动跳过片头/片尾
///
/// 判定思路（对齐 Animeko 的核心行为）：
/// - 片头：播放进度进入 [1s, opSeconds) 区间 → 跳到 opSeconds
/// - 片尾：剩余时长进入 (0, edSeconds] → 跳到末尾前 2 秒
/// 每个「番剧 + 集数」只自动跳一次；用户可取消。
class AutoSkipService {
  AutoSkipService._();

  static bool get enabled =>
      GStorage.getSetting(SettingsKeys.autoSkipOpEdEnabled);

  /// 记录 key = "bangumiId_episode"，避免切集/换源时状态串台
  static final Map<String, _SkipRecord> _records = {};

  static String _key(int bangumiId, int episode) => '${bangumiId}_$episode';

  /// 用户取消本次自动跳过（该番该集不再自动跳）
  static void cancel(int bangumiId, int episode) {
    _records.putIfAbsent(_key(bangumiId, episode), () => _SkipRecord())
        .cancelled = true;
  }

  /// 重置某一集（重新播放本集时用）
  static void reset(int bangumiId, int episode) {
    _records.remove(_key(bangumiId, episode));
  }

  static void resetAll() => _records.clear();

  static bool isOpSkipped(int bangumiId, int episode) =>
      _records[_key(bangumiId, episode)]?.opSkipped ?? false;
  static bool isEdSkipped(int bangumiId, int episode) =>
      _records[_key(bangumiId, episode)]?.edSkipped ?? false;
  static bool isCancelled(int bangumiId, int episode) =>
      _records[_key(bangumiId, episode)]?.cancelled ?? false;

  /// 计算自动跳转目标；无需跳转返回 null。
  ///
  /// 注意：这里**不再限制第 1 集/视频长度**——因为「片头时长」本身
  /// 就是用户按番设置的（0 = 不跳），如果用户设了 60 秒，第 1 集也该跳过。
  static Duration? target({
    required int bangumiId,
    required int episode,
    required Duration position,
    required Duration duration,
    required int opSeconds,
    required int edSeconds,
  }) {
    if (!enabled) return null;
    if (duration <= Duration.zero) return null;

    final rec = _records.putIfAbsent(_key(bangumiId, episode), () => _SkipRecord());
    if (rec.cancelled) return null;

    // ── 片头 ──
    if (opSeconds > 0 && !rec.opSkipped) {
      final opDur = Duration(seconds: opSeconds);
      // 片头必须比整片短（否则不可能是片头）
      if (opDur < duration) {
        // 进入片头区间：位置跨过 1 秒后、且还没到片头结束
        if (position >= const Duration(seconds: 1) && position < opDur) {
          rec.opSkipped = true;
          KazumiLogger().i(
              'AutoSkip: 片头 {pos=${position.inSeconds}s → op=${opSeconds}s}');
          return opDur;
        }
        // ⚠️ 位置已越过片头结束点：
        //   不能立即标记 opSkipped —— 因为 duration 可能加载很慢，
        //   视频「秒开」时位置可能已经跑到片头之后。只有确认
        //   duration 已稳定（>= 片头+60s 说明元数据已就绪）才认为真的错过。
        if (position >= opDur &&
            duration >= opDur + const Duration(seconds: 60)) {
          rec.opSkipped = true;
        }
      }
    }

    // ── 片尾 ──
    if (edSeconds > 0 && !rec.edSkipped) {
      final edDur = Duration(seconds: edSeconds);
      if (edDur < duration) {
        final target = duration - const Duration(seconds: 2);
        // 进入片尾区间：剩余时长已小于片尾时长
        if (position > Duration.zero && position < target) {
          final remaining = duration - position;
          if (remaining <= edDur) {
            rec.edSkipped = true;
            KazumiLogger().i(
                'AutoSkip: 片尾 {remaining=${remaining.inSeconds}s → 跳至 ${target.inSeconds}s}');
            return target;
          }
        }
      }
    }

    return null;
  }
}

class _SkipRecord {
  bool opSkipped = false;
  bool edSkipped = false;
  bool cancelled = false;
}

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 自动跳过片头/片尾（对齐 Animeko 的行为，适配本项目结构）
///
/// 原理：
/// 1. 本项目用「按番记忆的片头/片尾时长」（手动 > 众包 > 全局默认），
///    得到 op 秒 / ed 秒。
/// 2. 进入片头区间 → 自动 seek 到 op 秒；进入片尾区间 → 自动 seek 到结尾前 2 秒。
/// 3. 只在「本集」跳一次（跳过后不再重复），且用户可取消本次自动跳过。
/// 4. 第 1 集不自动跳（避免片头就是内容，例如第一集没 OP）。
class AutoSkipService {
  AutoSkipService._();

  /// 是否开启自动跳过（全局设置，默认开启）
  static bool get enabled =>
      GStorage.getSetting(SettingsKeys.autoSkipOpEdEnabled);

  /// 该集（番剧）是否已自动跳过（按 bangumiId 记录，切集会清）
  static final Map<int, _SkipRecord> _records = {};

  /// 手动取消：本次不再自动跳该番
  static void cancel(int bangumiId) {
    final rec = _records.putIfAbsent(bangumiId, () => _SkipRecord());
    rec.cancelled = true;
  }

  /// 切换番剧/集数时重置记录
  static void reset(int bangumiId) {
    _records.remove(bangumiId);
  }

  static void resetAll() => _records.clear();

  /// 是否已自动跳过片头 / 片尾（供 UI 显示状态）
  static bool isOpSkipped(int bangumiId) =>
      _records[bangumiId]?.opSkipped ?? false;
  static bool isEdSkipped(int bangumiId) =>
      _records[bangumiId]?.edSkipped ?? false;
  static bool isCancelled(int bangumiId) =>
      _records[bangumiId]?.cancelled ?? false;

  /// 计算是否需要自动跳过
  ///
  /// 返回需要跳转到的目标时长；无需跳转时返回 null。
  ///
  /// [bangumiId] 番剧 id
  /// [episode]   当前集数（第 1 集不自动跳）
  /// [position]  当前播放位置
  /// [duration]  视频总时长
  /// [opSeconds]/[edSeconds] 片头/片尾时长（0 = 不跳）
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
    // 第 1 集不自动跳过（第一集通常没有 OP/ED）
    if (episode <= 1) return null;
    // 视频太短（< 10 分钟）不跳，避免把正片当 OP/ED
    if (duration < const Duration(minutes: 10)) return null;

    final rec = _records.putIfAbsent(bangumiId, () => _SkipRecord());
    if (rec.cancelled) return null;

    // ── 片头 ──
    if (opSeconds > 0 && !rec.opSkipped) {
      // 位于片头区间（播放超过 3 秒、还没过片头）
      if (position > const Duration(seconds: 3) &&
          position < Duration(seconds: opSeconds)) {
        rec.opSkipped = true;
        KazumiLogger().i('AutoSkip: 自动跳过片头 → ${opSeconds}s');
        return Duration(seconds: opSeconds);
      }
    }

    // ── 片尾 ──
    final remaining = duration - position;
    if (edSeconds > 0 && !rec.edSkipped) {
      // 剩余时长进入片尾区间（且视频总长足够）
      if (remaining > const Duration(seconds: 2) &&
          remaining <= Duration(seconds: edSeconds)) {
        rec.edSkipped = true;
        final target = duration - const Duration(seconds: 2);
        KazumiLogger().i('AutoSkip: 自动跳过片尾 → ${target.inSeconds}s');
        return target;
      }
    }

    return null;
  }

  /// 用户手动拖回片头区间时调用：撤销"已跳过"标记，允许再次自动跳
  /// （例如拖回开始位置重新看片头）
  static void allowRetry(int bangumiId) {
    final rec = _records[bangumiId];
    if (rec == null) return;
    rec.opSkipped = false;
    rec.edSkipped = false;
  }
}

class _SkipRecord {
  bool opSkipped = false;
  bool edSkipped = false;
  bool cancelled = false;
}

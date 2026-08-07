import 'dart:async';
import 'dart:convert';

import 'package:kazumi/request/apis/skip_report_api.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 片头/片尾跳过时长（按番剧记忆 + 众包）
///
/// - 全局默认时长：设置页可调（默认 60 秒）
/// - 每个番剧可单独设置（key = bangumiId），覆盖全局默认
/// - 未手动设置时自动使用【众包时长】（全用户统计），众包没有才用默认
/// - 手动设置/调整时会上报服务器，帮助众包
class SkipSegmentsService {
  SkipSegmentsService._();

  /// 全局默认片头时长（秒），设置页可改
  static int get defaultOpSeconds =>
      GStorage.getSetting(SettingsKeys.skipOpDefaultSeconds);

  /// 全局默认片尾时长（秒），设置页可改
  static int get defaultEdSeconds =>
      GStorage.getSetting(SettingsKeys.skipEdDefaultSeconds);

  /// 众包时长缓存（bangumiId → 秒）
  static final Map<int, int> _crowdOp = {};
  static final Map<int, int> _crowdEd = {};

  static Map<int, int> _load(SettingKey<String> key) {
    try {
      final raw = GStorage.getSetting(key) as String;
      if (raw.isEmpty) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(int.tryParse(k) ?? -1, (v as num).round()));
    } catch (_) {
      return {};
    }
  }

  static void _save(SettingKey<String> key, Map<int, int> data) {
    GStorage.putSetting(key, jsonEncode(data));
  }

  /// 某番剧的片头时长（秒）：手动 > 众包 > 默认
  static int opSeconds(int bangumiId) {
    final manual = _load(SettingsKeys.skipOpDurations)[bangumiId];
    if (manual != null) return manual;
    final crowd = _crowdOp[bangumiId];
    if (crowd != null && crowd > 0) return crowd;
    return defaultOpSeconds;
  }

  /// 某番剧的片尾时长（秒）：手动 > 众包 > 默认
  static int edSeconds(int bangumiId) {
    final manual = _load(SettingsKeys.skipEdDurations)[bangumiId];
    if (manual != null) return manual;
    final crowd = _crowdEd[bangumiId];
    if (crowd != null && crowd > 0) return crowd;
    return defaultEdSeconds;
  }

  static void setOpSeconds(int bangumiId, int seconds) {
    final m = _load(SettingsKeys.skipOpDurations);
    m[bangumiId] = seconds;
    _save(SettingsKeys.skipOpDurations, m);
    unawaited(report(bangumiId));
  }

  static void setEdSeconds(int bangumiId, int seconds) {
    final m = _load(SettingsKeys.skipEdDurations);
    m[bangumiId] = seconds;
    _save(SettingsKeys.skipEdDurations, m);
    unawaited(report(bangumiId));
  }

  /// ⭐ 上报该番片头/片尾时长到众包服务器（手动设置/跳过后调用）
  static Future<void> report(int bangumiId) async {
    await SkipReportApi.report(
      subjectId: bangumiId,
      opMs: opSeconds(bangumiId) * 1000,
      edMs: edSeconds(bangumiId) * 1000,
    );
  }

  /// ⭐ 拉取该番众包时长并缓存（进入播放页时调用）
  static Future<void> fetchCrowd(int bangumiId) async {
    final res = await SkipReportApi.fetch(bangumiId);
    if (res == null) return;
    if (res.opMs > 0) _crowdOp[bangumiId] = (res.opMs / 1000).round();
    if (res.edMs > 0) _crowdEd[bangumiId] = (res.edMs / 1000).round();
  }
}

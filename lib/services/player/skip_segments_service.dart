import 'dart:convert';

import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 片头/片尾跳过时长（按番剧记忆）
///
/// - 全局默认时长：设置页可调（默认 60 秒）
/// - 每个番剧可单独设置（key = bangumiId），覆盖全局默认
/// - 换季（新番剧 id）不沿用，需重新设置
class SkipSegmentsService {
  SkipSegmentsService._();

  /// 全局默认片头时长（秒），设置页可改
  static int get defaultOpSeconds =>
      GStorage.getSetting(SettingsKeys.skipOpDefaultSeconds);

  /// 全局默认片尾时长（秒），设置页可改
  static int get defaultEdSeconds =>
      GStorage.getSetting(SettingsKeys.skipEdDefaultSeconds);

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

  /// 某番剧的片头时长（秒），未单独设置则用全局默认
  static int opSeconds(int bangumiId) =>
      _load(SettingsKeys.skipOpDurations)[bangumiId] ?? defaultOpSeconds;

  /// 某番剧的片尾时长（秒），未单独设置则用全局默认
  static int edSeconds(int bangumiId) =>
      _load(SettingsKeys.skipEdDurations)[bangumiId] ?? defaultEdSeconds;

  static void setOpSeconds(int bangumiId, int seconds) {
    final m = _load(SettingsKeys.skipOpDurations);
    m[bangumiId] = seconds;
    _save(SettingsKeys.skipOpDurations, m);
  }

  static void setEdSeconds(int bangumiId, int seconds) {
    final m = _load(SettingsKeys.skipEdDurations);
    m[bangumiId] = seconds;
    _save(SettingsKeys.skipEdDurations, m);
  }
}

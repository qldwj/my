import 'dart:convert';

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 按番剧记忆播放倍速
///
/// 数据以 JSON 字符串存放在 GStorage（{"subjectId": 倍速}）。
/// 同一部番换集/换线路播放时自动恢复上次倍速；用户手动改倍速时自动更新。
class PlaySpeedMemoryService {
  PlaySpeedMemoryService._();

  static Map<int, double>? _cache;

  static Map<int, double> _load() {
    if (_cache != null) return _cache!;
    try {
      final raw = GStorage.getSetting(SettingsKeys.playSpeedMemory);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      _cache = decoded.map((k, v) =>
          MapEntry(int.tryParse(k.toString()) ?? -1, (v as num).toDouble()));
      return _cache!;
    } catch (e) {
      KazumiLogger().w('PlaySpeedMemory: load failed', error: e);
      return {};
    }
  }

  static Future<void> _save(Map<int, double> data) async {
    _cache = data;
    await GStorage.putSetting(SettingsKeys.playSpeedMemory, jsonEncode(data));
  }

  /// 某番剧记忆的倍速（无记录返回 null）
  static double? getSpeed(int bangumiId) {
    final speed = _load()[bangumiId];
    if (speed == null || speed <= 0) return null;
    return speed;
  }

  /// 记录某番剧的倍速
  static Future<void> setSpeed(int bangumiId, double speed) async {
    if (bangumiId <= 0) return;
    try {
      final data = _load();
      final normalized = speed <= 0 ? 1.0 : speed;
      if (data[bangumiId] == normalized) return;
      data[bangumiId] = normalized;
      await _save(data);
    } catch (e) {
      KazumiLogger().w('PlaySpeedMemory: save failed', error: e);
    }
  }

  /// 清除某番剧的记忆
  static Future<void> clear(int bangumiId) async {
    final data = _load();
    data.remove(bangumiId);
    await _save(data);
  }

  /// 清除全部记忆
  static Future<void> clearAll() async {
    await _save({});
  }
}

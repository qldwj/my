import 'dart:async';
import 'dart:convert';

import 'package:kazumi/request/apis/skip_report_api.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 片头/片尾跳过时长（按番剧记忆 + 众包）
class SkipSegmentsService {
  SkipSegmentsService._();

  /// 全局默认片头时长（秒）
  static int get defaultOpSeconds =>
      GStorage.getSetting(SettingsKeys.skipOpDefaultSeconds);

  /// 全局默认片尾时长（秒）
  static int get defaultEdSeconds =>
      GStorage.getSetting(SettingsKeys.skipEdDefaultSeconds);

  /// 众包时长缓存
  static final Map<int, int> _crowdOp = {};
  static final Map<int, int> _crowdEd = {};

  /// 手动设置缓存（避免频繁读 GStorage）
  static Map<int, int>? _manualOpCache;
  static Map<int, int>? _manualEdCache;

  static Map<int, int> _loadOp() {
    if (_manualOpCache != null) return _manualOpCache!;
    try {
      final raw = GStorage.getSetting(SettingsKeys.skipOpDurations) as String?;
      if (raw == null || raw.isEmpty) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _manualOpCache = map.map((k, v) =>
          MapEntry(int.tryParse(k) ?? -1, (v as num).round()));
      return _manualOpCache!;
    } catch (_) {
      return {};
    }
  }

  static Map<int, int> _loadEd() {
    if (_manualEdCache != null) return _manualEdCache!;
    try {
      final raw = GStorage.getSetting(SettingsKeys.skipEdDurations) as String?;
      if (raw == null || raw.isEmpty) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _manualEdCache = map.map((k, v) =>
          MapEntry(int.tryParse(k) ?? -1, (v as num).round()));
      return _manualEdCache!;
    } catch (_) {
      return {};
    }
  }

  static void _saveOp(Map<int, int> data) {
    _manualOpCache = data;
    GStorage.putSetting(SettingsKeys.skipOpDurations, jsonEncode(data));
  }

  static void _saveEd(Map<int, int> data) {
    _manualEdCache = data;
    GStorage.putSetting(SettingsKeys.skipEdDurations, jsonEncode(data));
  }

  /// 某番剧的片头时长（秒）：手动 > 众包 > 默认
  static int opSeconds(int bangumiId) {
    final manual = _loadOp()[bangumiId];
    if (manual != null && manual > 0) return manual;
    final crowd = _crowdOp[bangumiId];
    if (crowd != null && crowd > 0) return crowd;
    return defaultOpSeconds;
  }

  /// 某番剧的片尾时长（秒）：手动 > 众包 > 默认
  static int edSeconds(int bangumiId) {
    final manual = _loadEd()[bangumiId];
    if (manual != null && manual > 0) return manual;
    final crowd = _crowdEd[bangumiId];
    if (crowd != null && crowd > 0) return crowd;
    return defaultEdSeconds;
  }

  static void setOpSeconds(int bangumiId, int seconds) {
    final m = _loadOp();
    if (seconds <= 0) {
      m.remove(bangumiId);
    } else {
      m[bangumiId] = seconds;
    }
    _saveOp(m);
    // ⭐ 上报众包
    unawaited(report(bangumiId));
  }

  static void setEdSeconds(int bangumiId, int seconds) {
    final m = _loadEd();
    if (seconds <= 0) {
      m.remove(bangumiId);
    } else {
      m[bangumiId] = seconds;
    }
    _saveEd(m);
    // ⭐ 上报众包
    unawaited(report(bangumiId));
  }

  /// 清除某番剧的手动设置（恢复使用众包/默认）
  static void clearOpSeconds(int bangumiId) {
    final m = _loadOp();
    m.remove(bangumiId);
    _saveOp(m);
  }

  static void clearEdSeconds(int bangumiId) {
    final m = _loadEd();
    m.remove(bangumiId);
    _saveEd(m);
  }

  /// 上报该番片头/片尾时长到众包服务器
  static Future<void> report(int bangumiId) async {
    await SkipReportApi.report(
      subjectId: bangumiId,
      opMs: opSeconds(bangumiId) * 1000,
      edMs: edSeconds(bangumiId) * 1000,
    );
  }

  /// 拉取该番众包时长并缓存
  static Future<void> fetchCrowd(int bangumiId) async {
    final res = await SkipReportApi.fetch(bangumiId);
    if (res == null) return;
    if (res.opMs > 0) _crowdOp[bangumiId] = (res.opMs / 1000).round();
    if (res.edMs > 0) _crowdEd[bangumiId] = (res.edMs / 1000).round();
  }

  /// ⭐ 强制刷新缓存（用于调试/页面刷新）
  static void refreshCache() {
    _manualOpCache = null;
    _manualEdCache = null;
  }
}
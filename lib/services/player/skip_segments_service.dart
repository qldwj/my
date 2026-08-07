import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kazumi/request/apis/skip_report_api.dart';

/// 片头/片尾跳过时长（按番剧记忆 + 众包）
///
/// - 全局默认时长：设置页可调（默认 60 秒）
/// - 每个番剧可单独设置（key = bangumiId），覆盖全局默认
/// - 未手动设置时自动使用【众包时长】（全用户统计），众包没有才用默认
/// - 手动设置/调整时会上报服务器，帮助众包
class SkipSegmentsService {
  SkipSegmentsService._();

  static const String _keyOpDefault = 'skip_op_default';
  static const String _keyEdDefault = 'skip_ed_default';
  static const String _keyOpDurations = 'skip_op_durations';
  static const String _keyEdDurations = 'skip_ed_durations';

  static SharedPreferences? _prefs;
  static bool _initialized = false;

  /// 确保 SharedPreferences 已初始化
  static Future<void> _ensureInit() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  /// 全局默认片头时长（秒），设置页可改
  static int get defaultOpSeconds {
    _ensureInit();
    return _prefs?.getInt(_keyOpDefault) ?? 60;
  }

  /// 全局默认片尾时长（秒），设置页可改
  static int get defaultEdSeconds {
    _ensureInit();
    return _prefs?.getInt(_keyEdDefault) ?? 60;
  }

  /// 设置全局默认片头时长
  static void setDefaultOpSeconds(int seconds) {
    _ensureInit();
    _prefs?.setInt(_keyOpDefault, seconds);
  }

  /// 设置全局默认片尾时长
  static void setDefaultEdSeconds(int seconds) {
    _ensureInit();
    _prefs?.setInt(_keyEdDefault, seconds);
  }

  /// 众包时长缓存（bangumiId → 秒）
  static final Map<int, int> _crowdOp = {};
  static final Map<int, int> _crowdEd = {};

  static Map<int, int> _loadOp() {
    _ensureInit();
    try {
      final raw = _prefs?.getString(_keyOpDurations);
      if (raw == null || raw.isEmpty) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(int.tryParse(k) ?? -1, (v as num).round()));
    } catch (_) {
      return {};
    }
  }

  static Map<int, int> _loadEd() {
    _ensureInit();
    try {
      final raw = _prefs?.getString(_keyEdDurations);
      if (raw == null || raw.isEmpty) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(int.tryParse(k) ?? -1, (v as num).round()));
    } catch (_) {
      return {};
    }
  }

  static void _saveOp(Map<int, int> data) {
    _ensureInit();
    _prefs?.setString(_keyOpDurations, jsonEncode(data));
  }

  static void _saveEd(Map<int, int> data) {
    _ensureInit();
    _prefs?.setString(_keyEdDurations, jsonEncode(data));
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
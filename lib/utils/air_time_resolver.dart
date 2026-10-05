import 'package:yhdm/modules/bangumi/bangumi_item.dart';

/// 🆕 播出时间推算（本地纯函数，不请求额外网络）
///
/// 现有 calendar 数据只含 airDate（YYYY-MM-DD）与 airWeekday（1-7，周一=1），
/// 不含精确到分钟的 broadcast 字段。这里基于这两者做「尽量精确」的推算：
/// - 有 airDate：显示日期 + 星期
/// - 有 airWeekday：显示星期
/// 纯 UI 展示辅助，不改动现有数据模型。
class AirTimeResolver {
  AirTimeResolver._();

  static const List<String> _weekdays = [
    '周一', '周二', '周三', '周四', '周五', '周六', '周日',
  ];

  /// 星期几文字（airWeekday: 1=周一 ... 7=周日）
  static String weekdayText(int airWeekday) {
    if (airWeekday < 1 || airWeekday > 7) return '';
    return _weekdays[airWeekday - 1];
  }

  /// 从 airDate "YYYY-MM-DD" 提取年份
  static String yearOf(String airDate) {
    final m = RegExp(r'(\d{4})').firstMatch(airDate);
    return m?.group(1) ?? '';
  }

  /// 从 airDate 提取日期部分 "MM-DD"
  static String monthDayOf(String airDate) {
    final m = RegExp(r'\d{4}-(\d{2}-\d{2})').firstMatch(airDate);
    return m?.group(1) ?? '';
  }

  /// 播出状态推断：
  /// -1 = 未知/无效；0 = 未播出；1 = 已播出（按日期粗判）
  static int statusOf(String airDate) {
    final d = DateTime.tryParse(airDate);
    if (d == null) return -1;
    final today = DateTime.now();
    return d.isAfter(today) ? 0 : 1;
  }

  /// 组装时间表卡片 footer 的播出时间文案。
  /// 优先级：周X + MM-DD > 周X > 空。
  static String describe(BangumiItem item) {
    final wd = weekdayText(item.airWeekday);
    final md = monthDayOf(item.airDate);
    if (wd.isNotEmpty && md.isNotEmpty) return '$wd · $md';
    if (wd.isNotEmpty) return wd;
    return '';
  }

  /// 组装“是否已开播”文案（用于卡片角标/状态）。
  /// 未开播返回 true（显示🔒），已开播返回 false。
  static bool isUpcoming(BangumiItem item) {
    final status = statusOf(item.airDate);
    // 未知日期按已开播处理（连载中通常已有日期）
    if (status == -1) return false;
    return status == 0;
  }
}

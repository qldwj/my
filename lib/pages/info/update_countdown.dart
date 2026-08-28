import 'package:flutter/material.dart';

class UpdateCountdown extends StatelessWidget {
  final int airWeekday;
  final String airDate;
  final int? totalEps;

  const UpdateCountdown({
    super.key,
    required this.airWeekday,
    required this.airDate,
    this.totalEps,
  });

  static const _weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  /// 计算已播出集数（基于开播日期和当前日期）
  int _getAiredEpisodes() {
    if (airDate.isEmpty || airWeekday <= 0) return 0;
    try {
      final startDate = DateTime.parse(airDate);
      final now = DateTime.now();
      if (now.isBefore(startDate)) return 0;
      
      // 从开播日到今天经过的天数
      final daysPassed = now.difference(startDate).inDays;
      
      // 开播日是星期几
      final startWeekday = startDate.weekday;
      
      // 从开播到第一次更新需要等待的天数
      int daysToFirstUpdate = airWeekday - startWeekday;
      if (daysToFirstUpdate <= 0) daysToFirstUpdate += 7;
      
      // 第一集播出的日期
      final firstUpdate = startDate.add(Duration(days: daysToFirstUpdate));
      
      if (now.isBefore(firstUpdate)) return 0;
      
      // 从第一集到今天经过的天数，除以7得到集数
      final daysSinceFirst = now.difference(firstUpdate).inDays;
      return (daysSinceFirst ~/ 7) + 1;
    } catch (_) {
      return 0;
    }
  }

  /// 计算下次更新的倒计时
  String _getNextUpdateCountdown() {
    if (airWeekday <= 0) return '';
    
    final now = DateTime.now();
    final currentWeekday = now.weekday;
    
    // 计算距离下一个更新日还有几天
    int daysUntil = airWeekday - currentWeekday;
    if (daysUntil < 0) daysUntil += 7;
    if (daysUntil == 0) {
      // 今天是更新日，检查是否已过更新时间（假设下午2点更新）
      final todayUpdate = DateTime(now.year, now.month, now.day, 14, 0);
      if (now.isBefore(todayUpdate)) {
        return '今天 ${todayUpdate.difference(now).inHours}小时后';
      } else {
        daysUntil = 7;
      }
    }
    
    if (daysUntil == 1) return '明天';
    if (daysUntil == 2) return '后天';
    if (daysUntil <= 7) return '${daysUntil}天后';
    return '${daysUntil}天后';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final weekdayName = (airWeekday > 0 && airWeekday <= 7) ? _weekdayNames[airWeekday] : '';
    final airedEps = _getAiredEpisodes();
    final nextUpdate = _getNextUpdateCountdown();

    if (weekdayName.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text('每周$weekdayName更新',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
          const SizedBox(width: 12),
          Text('已更新$airedEps集',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          if (nextUpdate.isNotEmpty) ...[
            const Spacer(),
            Text('下次 $nextUpdate',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
          ],
        ],
      ),
    );
  }
}

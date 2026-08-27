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

  DateTime _getNextUpdate() {
    final now = DateTime.now();
    if (airWeekday <= 0 || airWeekday > 7) return now;
    int daysUntil = airWeekday - now.weekday;
    if (daysUntil <= 0) daysUntil += 7;
    return now.add(Duration(days: daysUntil));
  }

  int _getAiredEpisodes() {
    if (airDate.isEmpty) return 0;
    try {
      final startDate = DateTime.parse(airDate);
      final now = DateTime.now();
      if (now.isBefore(startDate)) return 0;
      return (now.difference(startDate).inDays ~/ 7) + 1;
    } catch (_) {
      return 0;
    }
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}天${d.inHours % 24}小时';
    if (d.inHours > 0) return '${d.inHours}小时${d.inMinutes % 60}分钟';
    return '${d.inMinutes}分钟';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nextUpdate = _getNextUpdate();
    final duration = nextUpdate.difference(DateTime.now());
    final weekdayName = (airWeekday > 0 && airWeekday <= 7) ? _weekdayNames[airWeekday] : '';
    final airedEps = _getAiredEpisodes();

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
          const Spacer(),
          Text('下次 ${_formatDuration(duration)}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
        ],
      ),
    );
  }
}

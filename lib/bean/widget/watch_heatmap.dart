import 'package:flutter/material.dart';

/// 观看热力图（GitHub 绿点风格）
///
/// 行 = 周一~周日，列 = 周；颜色深浅表示当天观看集数。
/// [dailyCounts] 的 key 需归一化为「当天 0 点」（year,month,day）。
class WatchHeatmap extends StatelessWidget {
  const WatchHeatmap({super.key, required this.dailyCounts});

  final Map<DateTime, int> dailyCounts;

  static const int _weeks = 53;
  static const double _cell = 11;
  static const double _gap = 3;

  int _countAt(DateTime day) => dailyCounts[day] ?? 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(Duration(days: _weeks * 7 - 1));

    Color cellColor(int count) {
      if (count <= 0) return colors.surfaceContainerHighest;
      final alpha = count >= 8
          ? 1.0
          : count >= 5
              ? 0.75
              : count >= 3
                  ? 0.5
                  : 0.3;
      return colors.primary.withValues(alpha: alpha);
    }

    final totalDays = _countAt(DateTime(now.year, now.month, now.day));
    var activeDays = 0;
    var totalEpisodes = 0;
    for (final v in dailyCounts.values) {
      if (v > 0) activeDays++;
      totalEpisodes += v;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var w = 0; w < _weeks; w++)
                Padding(
                  padding: EdgeInsets.only(right: _gap),
                  child: Column(
                    children: [
                      for (var r = 0; r < 7; r++)
                        Padding(
                          padding: EdgeInsets.only(bottom: _gap),
                          child: Container(
                            width: _cell,
                            height: _cell,
                            decoration: BoxDecoration(
                              color: cellColor(
                                  _countAt(start.add(Duration(days: w * 7 + r)))),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('近一年观看热力图',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant)),
            const Spacer(),
            Text('今天 $totalDays 集',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.primary, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Text('累计活跃 $activeDays 天 · 共 $totalEpisodes 集',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.onSurfaceVariant)),
      ],
    );
  }
}

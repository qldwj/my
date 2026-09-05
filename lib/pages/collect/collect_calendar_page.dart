import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 追番日历：把收藏中"在看"的番剧按放送星期展示
///
/// 数据来源：本地收藏（type==1 在看）+ 每条目的 airWeekday。
/// 未知放送日的番剧归入"未排期"。
class CollectCalendarPage extends StatefulWidget {
  const CollectCalendarPage({super.key});

  @override
  State<CollectCalendarPage> createState() => _CollectCalendarPageState();
}

class _CollectCalendarPageState extends State<CollectCalendarPage> {
  static const List<String> _weekdayNames = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  late final Map<int, List<BangumiItem>> _byDay;

  @override
  void initState() {
    super.initState();
    _byDay = _buildCalendar();
  }

  Map<int, List<BangumiItem>> _buildCalendar() {
    final result = <int, List<BangumiItem>>{};
    for (var i = 0; i < 7; i++) {
      result[i + 1] = [];
    }
    result[0] = []; // 未排期
    try {
      final watching = GStorage.collectibles.values
          .where((c) => c.type == 1) // 在看
          .toList()
        ..sort((a, b) => b.time.millisecondsSinceEpoch
            .compareTo(a.time.millisecondsSinceEpoch));
      for (final c in watching) {
        final weekday = c.bangumiItem.airWeekday;
        final key = (weekday >= 1 && weekday <= 7) ? weekday : 0;
        result[key]!.add(c.bangumiItem);
      }
    } catch (_) {}
    return result;
  }

  int get _todayWeekday => DateTime.now().weekday;

  int _crossCount() {
    final width = MediaQuery.sizeOf(context).width;
    if (width > 1400) return 6;
    if (width > 1000) return 5;
    if (width > 700) return 4;
    return 3;
  }

  double _cardExtent(int crossCount) {
    return MediaQuery.sizeOf(context).width / crossCount / 0.65 +
        MediaQuery.textScalerOf(context).scale(32.0);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final crossCount = _crossCount();
    final hasAny =
        _byDay.values.any((list) => list.isNotEmpty);
    return Scaffold(
      appBar: SysAppBar(title: const Text('追番日历')),
      body: !hasAny
          ? const Center(
              child: GeneralEmptyState(
                icon: Icons.calendar_month_outlined,
                title: '暂无"在看"的番剧',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (var day = 1; day <= 7; day++)
                  if (_byDay[day]!.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: day == _todayWeekday
                                  ? colorScheme.primary
                                  : colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _weekdayNames[day - 1],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: day == _todayWeekday
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_byDay[day]!.length} 部',
                            style: TextStyle(
                                fontSize: 12, color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossCount,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        mainAxisExtent: _cardExtent(crossCount),
                      ),
                      itemCount: _byDay[day]!.length,
                      itemBuilder: (context, index) => BangumiCardV(
                        bangumiItem: _byDay[day]![index],
                        canTap: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                if (_byDay[0]!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '未排期',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_byDay[0]!.length} 部',
                          style: TextStyle(
                              fontSize: 12, color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossCount,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      mainAxisExtent: _cardExtent(crossCount),
                    ),
                    itemCount: _byDay[0]!.length,
                    itemBuilder: (context, index) => BangumiCardV(
                      bangumiItem: _byDay[0]![index],
                      canTap: true,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

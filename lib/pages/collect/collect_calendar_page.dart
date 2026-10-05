import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/widget/empty_state_widget.dart';
import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/modules/collect/collect_module.dart';
import 'package:yhdm/services/schedule_service.dart';
import 'package:yhdm/services/storage/storage.dart';

/// 追番日历（Animeko 风格）
///
/// 数据：收藏中"在看"的番剧，放送规律（周几+时刻）从服务端 schedule.php 获取。
/// UI 完全模仿 Animeko：按天分组、天内按放送时间排序、今天插入"当前时间指示器"
/// （指示器前=已开播/现在能看，之后=接下来能看），时间未定的排最后。
class CollectCalendarPage extends StatefulWidget {
  const CollectCalendarPage({super.key});

  @override
  State<CollectCalendarPage> createState() => _CollectCalendarPageState();
}

class _CalItem {
  final BangumiItem item;
  final String? time; // "HH:mm"，null = 时间未定
  _CalItem(this.item, this.time);
}

class _CollectCalendarPageState extends State<CollectCalendarPage> {
  static const List<String> _weekdayNames = [
    '周一', '周二', '周三', '周四', '周五', '周六', '周日',
  ];

  Map<int, List<_CalItem>> _byDay = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<BangumiItem> watching = [];
    try {
      watching = GStorage.collectibles.values
          .where((c) => c.type == 1)
          .map((c) => c.bangumiItem)
          .toList();
    } catch (_) {}
    // 服务端放送规律
    final weekly = await ScheduleService.fetchWeekly(
      watching.map((e) => e.id).toList(),
      tz: 8,
    );
    if (!mounted) return;

    final result = <int, List<_CalItem>>{};
    for (var i = 0; i < 7; i++) {
      result[i + 1] = [];
    }
    result[0] = []; // 未排期
    for (final item in watching) {
      final w = weekly[item.id];
      int day;
      String? time;
      if (w != null) {
        day = w.dayOfWeek;
        time = w.time;
      } else {
        // fallback 本地 airWeekday（无精确时间）
        day = (item.airWeekday >= 1 && item.airWeekday <= 7)
            ? item.airWeekday
            : 0;
        time = null;
      }
      result[day]!.add(_CalItem(item, time));
    }
    // 天内：已知时间按时间升序，时间未定排最后
    for (final day in result.keys) {
      final timed = result[day]!
          .where((e) => e.time != null)
          .toList()
        ..sort((a, b) => a.time!.compareTo(b.time!));
      final untimed = result[day]!.where((e) => e.time == null).toList();
      result[day] = [...timed, ...untimed];
    }
    setState(() {
      _byDay = result;
      _loading = false;
    });
  }

  int get _todayWeekday => DateTime.now().weekday;
  String get _nowTimeStr {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasAny = _byDay.values.any((list) => list.isNotEmpty);

    return Scaffold(
      appBar: SysAppBar(title: const Text('追番日历')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !hasAny
              ? const Center(
                  child: GeneralEmptyState(
                    icon: Icons.calendar_month_outlined,
                    title: '暂无"在看"的番剧',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (var day = 1; day <= 7; day++)
                      if (_byDay[day]!.isNotEmpty)
                        _DaySection(
                          day: day,
                          isToday: day == _todayWeekday,
                          items: _byDay[day]!,
                          nowTimeStr: _nowTimeStr,
                        ),
                    if (_byDay[0]!.isNotEmpty)
                      _DaySection(
                        day: 0,
                        isToday: false,
                        items: _byDay[0]!,
                        nowTimeStr: _nowTimeStr,
                      ),
                  ],
                ),
    );
  }
}

/// 单日区块（Animeko ScheduleDayColumn 风格）
class _DaySection extends StatelessWidget {
  final int day; // 0=未排期, 1-7=周一..周日
  final bool isToday;
  final List<_CalItem> items;
  final String nowTimeStr;

  const _DaySection({
    required this.day,
    required this.isToday,
    required this.items,
    required this.nowTimeStr,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = day == 0 ? '未排期' : _weekdayName(day);

    // 今天：把已开播(time<=now)放前面，插入当前指示器，再放未开播
    List<Widget> children = [];
    if (isToday) {
      final passed =
          items.where((e) => e.time != null && e.time!.compareTo(nowTimeStr) <= 0).toList();
      final upcoming =
          items.where((e) => e.time != null && e.time!.compareTo(nowTimeStr) > 0).toList();
      final untimed = items.where((e) => e.time == null).toList();
      for (final e in passed) {
        children.add(_ScheduleItem(e.item, e.time, aired: true));
      }
      children.add(_CurrentTimeIndicator(nowTimeStr));
      for (final e in upcoming) {
        children.add(_ScheduleItem(e.item, e.time, aired: false));
      }
      for (final e in untimed) {
        children.add(_ScheduleItem(e.item, null, aired: false));
      }
    } else {
      for (final e in items) {
        children.add(_ScheduleItem(e.item, e.time, aired: true));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 星期标题 + 数量
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isToday
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
              ),
              if (isToday) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '今天',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                '${items.length} 部',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        if (isToday && items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: _CurrentTimeIndicator(nowTimeStr),
          ),
        ...children,
        const SizedBox(height: 6),
        Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ],
    );
  }

  static String _weekdayName(int d) =>
      const ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'][d];
}

/// 当前时间指示器（模仿 Animeko ScheduleCurrentTimeIndicator）
class _CurrentTimeIndicator extends StatelessWidget {
  final String nowTimeStr;
  const _CurrentTimeIndicator(this.nowTimeStr);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 0, 10),
            child: Row(
              children: [
                Icon(Icons.alarm_outlined, size: 18, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '现在 $nowTimeStr',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Divider(
            thickness: 1.5,
            color: colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

/// 单条目（模仿 Animeko ScheduleItem：海报 + 标题 + 时间）
class _ScheduleItem extends StatelessWidget {
  final BangumiItem item;
  final String? time;
  final bool aired;

  const _ScheduleItem(this.item, this.time, {required this.aired});

  String get _title =>
      (item.nameCn.isNotEmpty ? item.nameCn : item.name);

  String get _cover =>
      item.images['large'] ?? item.images['medium'] ?? item.images['grid'] ?? '';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = aired ? colorScheme.onSurface : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: () {
        context.pushNamed('/info/', arguments: item);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            // 海报
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 66,
                child: _cover.isEmpty
                    ? Container(color: colorScheme.surfaceContainerHighest)
                    : Image.network(
                        _cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.movie_outlined,
                              color: colorScheme.outline),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // 标题 + 时间
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.airDate.isNotEmpty
                        ? '${item.airDate} 放送'
                        : '连载中',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 放送时间 / 状态
            if (time != null)
              Text(
                time!,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: aired ? colorScheme.primary : colorScheme.outline,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_clock_outlined,
                      size: 14, color: colorScheme.outline),
                  const SizedBox(width: 3),
                  Text(
                    '时间未定',
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

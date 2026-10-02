import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/timeline/timeline_controller.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/utils/anime_season.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({
    super.key,
    required this.controller,
  });

  final TimelineController controller;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage>
    with SingleTickerProviderStateMixin {
  TimelineController get timelineController => widget.controller;
  TabController? tabController;
  final GlobalKey filterSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    int weekday = DateTime.now().weekday - 1;
    tabController =
        TabController(vsync: this, length: tabs.length, initialIndex: weekday);
    if (timelineController.bangumiCalendar.isEmpty) {
      timelineController.init();
    }
  }

  @override
  void dispose() {
    tabController?.dispose();
    super.dispose();
  }

  DateTime generateDateTime(int year, String season) {
    switch (season) {
      case '冬':
        return DateTime(year, 1, 1);
      case '春':
        return DateTime(year, 4, 1);
      case '夏':
        return DateTime(year, 7, 1);
      case '秋':
        return DateTime(year, 10, 1);
      default:
        return DateTime.now();
    }
  }

  final List<Tab> tabs = const <Tab>[
    Tab(text: '一'),
    Tab(text: '二'),
    Tab(text: '三'),
    Tab(text: '四'),
    Tab(text: '五'),
    Tab(text: '六'),
    Tab(text: '日'),
  ];

  final seasons = ['秋', '夏', '春', '冬'];

  String getStringByDateTime(DateTime d) {
    return d.year.toString() + getSeasonStringByMonth(d.month);
  }

  Future<void> scrollToFilterSection() async {
    final filterContext = filterSectionKey.currentContext;
    if (filterContext == null) {
      return;
    }

    await Scrollable.ensureVisible(
      filterContext,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  BoxConstraints buildTimelineBottomSheetConstraints(
    BuildContext context, {
    double? compactHeightFactor,
  }) {
    final mediaSize = MediaQuery.sizeOf(context);
    final adaptiveConstraints = adaptiveBottomSheetConstraints(context);
    final maxHeight = compactHeightFactor != null
        ? (mediaSize.height >= LayoutBreakpoint.compact['height']!
            ? mediaSize.height * compactHeightFactor
            : mediaSize.height)
        : double.infinity;

    return BoxConstraints(
      maxWidth: adaptiveConstraints.maxWidth,
      maxHeight: maxHeight,
    );
  }

  Widget buildTimelineBottomSheetShell(
    BuildContext context, {
    required Widget header,
    required Widget body,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          Flexible(child: body),
        ],
      ),
    );
  }

  void showSeasonBottomSheet(BuildContext context) {
    final currDate = DateTime.now();
    final years = List.generate(20, (index) => currDate.year - index);

    // 按年份分组生成可用季节
    final yearSeasons = <int, List<DateTime>>{};
    for (final year in years) {
      final availableSeasons = <DateTime>[];
      for (final season in seasons) {
        final date = generateDateTime(year, season);
        if (currDate.isAfter(date)) {
          availableSeasons.add(date);
        }
      }
      if (availableSeasons.isNotEmpty) {
        yearSeasons[year] = availableSeasons;
      }
    }

    KazumiDialog.showBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      useSafeArea: true,
      constraints: buildTimelineBottomSheetConstraints(context),
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return buildTimelineBottomSheetShell(
              sheetContext,
              header: buildSeasonSheetHeader(sheetContext),
              body: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                itemCount: yearSeasons.keys.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final year = yearSeasons.keys.elementAt(index);
                  final availableSeasons = yearSeasons[year]!;

                  return buildSeasonYearSection(
                    context,
                    year,
                    availableSeasons,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget buildSeasonSheetHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return MaterialBottomSheetHeader(
      title: '时间机器',
      description: '按季度回到任意放送季，时间线会立即切换。',
      onClose: KazumiDialog.dismiss,
      footer: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '当前查看 ${getStringByDateTime(timelineController.selectedDate)}',
          style: textTheme.labelLarge?.copyWith(
            color: colorScheme.onSecondaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  DateTime? getSelectedSeason(List<DateTime> availableSeasons) {
    for (final season in availableSeasons) {
      if (isSameSeason(timelineController.selectedDate, season)) {
        return season;
      }
    }

    return null;
  }

  Widget buildSeasonYearSection(
      BuildContext context, int year, List<DateTime> availableSeasons) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasSelectedSeason = getSelectedSeason(availableSeasons) != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: hasSelectedSeason
            ? colorScheme.secondaryContainer.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasSelectedSeason
              ? colorScheme.secondary.withValues(alpha: 0.24)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$year年',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!hasSelectedSeason) ...[
            const SizedBox(height: 4),
            Text(
              '共 ${availableSeasons.length} 个季度可选',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          buildSeasonChoiceChips(context, availableSeasons),
        ],
      ),
    );
  }

  Widget buildSeasonChoiceChips(
      BuildContext context, List<DateTime> availableSeasons) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selectedSeason = getSelectedSeason(availableSeasons);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: availableSeasons.map((date) {
        final seasonName = getSeasonStringByMonth(date.month);
        final isSelected =
            selectedSeason != null && isSameSeason(selectedSeason, date);

        return ChoiceChip(
          label: Text(seasonName),
          selected: isSelected,
          onSelected: (selected) {
            if (!selected) {
              return;
            }
            KazumiDialog.dismiss();
            onSeasonSelected(date);
          },
          showCheckmark: false,
          labelStyle: textTheme.labelLarge?.copyWith(
            color: isSelected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: colorScheme.surfaceContainerHigh,
          selectedColor: colorScheme.secondaryContainer,
          side: BorderSide(
            color: isSelected
                ? Colors.transparent
                : colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }

  void onSeasonSelected(DateTime date) async {
    final currDate = DateTime.now();
    timelineController.tryEnterSeason(date);

    if (isSameSeason(timelineController.selectedDate, currDate)) {
      await timelineController.getSchedules();
    } else {
      await timelineController.getSchedulesBySeason();
    }

    timelineController.seasonString =
        AnimeSeason(timelineController.selectedDate).toString();
  }

  String getSortTypeLabel(int sortType) {
    switch (sortType) {
      case 1:
        return '时间优先';
      case 2:
        return '评分优先';
      case 3:
        return '热度优先';
      default:
        return '热度优先';
    }
  }

  int getEnabledTimelineFilterCount() {
    var enabledCount = 0;
    if (timelineController.notShowAbandonedBangumis) {
      enabledCount++;
    }
    if (timelineController.notShowWatchedBangumis) {
      enabledCount++;
    }
    if (timelineController.onlyShowWatchingBangumis) {
      enabledCount++;
    }
    return enabledCount;
  }

  Widget buildTimelineOptionSummaryChip(
    BuildContext context, {
    required String label,
    bool highlighted = false,
    VoidCallback? onTap,
    IconData? trailingIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foregroundColor =
        highlighted ? colorScheme.onSecondaryContainer : colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: highlighted
                ? colorScheme.secondaryContainer
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: textTheme.labelLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 6),
                Icon(
                  trailingIcon,
                  size: 18,
                  color: foregroundColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget buildTimelineOptionsSheetHeader(BuildContext context) {
    return MaterialBottomSheetHeader(
      title: '时间线选项',
      description: '调整排序和过滤条件，结果会立即应用到当前时间线。',
      onClose: KazumiDialog.dismiss,
      footer: Observer(
        builder: (context) {
          final enabledFilterCount = getEnabledTimelineFilterCount();
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              buildTimelineOptionSummaryChip(
                context,
                label: '当前排序 ${getSortTypeLabel(timelineController.sortType)}',
                highlighted: true,
              ),
              buildTimelineOptionSummaryChip(
                context,
                label: enabledFilterCount == 0
                    ? '未启用过滤条件'
                    : '已启用 $enabledFilterCount 个过滤条件',
                onTap: scrollToFilterSection,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget buildSortOptionTile(
    BuildContext context, {
    required int sortType,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = timelineController.sortType == sortType;

    return Ink(
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? colorScheme.secondary.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: Icon(
          icon,
          color: isSelected
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            color: isSelected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          description,
          style: textTheme.bodySmall?.copyWith(
            color: isSelected
                ? colorScheme.onSecondaryContainer.withValues(alpha: 0.82)
                : colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          isSelected
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          color: isSelected
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        ),
        onTap: () {
          KazumiDialog.dismiss();
          timelineController.changeSortType(sortType);
        },
      ),
    );
  }

  Widget buildFilterOptionTile(
    BuildContext context, {
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Ink(
      decoration: BoxDecoration(
        color: value
            ? colorScheme.secondaryContainer.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: value
              ? colorScheme.secondary.withValues(alpha: 0.24)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: Icon(
          icon,
          color: value
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            color: value
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          description,
          style: textTheme.bodySmall?.copyWith(
            color: value
                ? colorScheme.onSecondaryContainer.withValues(alpha: 0.82)
                : colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
        ),
        onTap: () {
          onChanged(!value);
        },
      ),
    );
  }

  Widget showFilterSwitcher() {
    return MaterialBottomSheetSection(
      key: filterSectionKey,
      title: '过滤器',
      description: '按收藏状态收起不需要显示的条目，支持连续调整。',
      child: Column(
        children: [
          Observer(
            builder: (context) => buildFilterOptionTile(
              context,
              title: '不显示已抛弃的番剧',
              description: '隐藏已经标记为抛弃的条目。',
              value: timelineController.notShowAbandonedBangumis,
              onChanged: (value) {
                timelineController.setNotShowAbandonedBangumis(value);
              },
              icon: Icons.heart_broken_rounded,
            ),
          ),
          const SizedBox(height: 12),
          Observer(
            builder: (context) => buildFilterOptionTile(
              context,
              title: '不显示已看过的番剧',
              description: '把已经看完的条目从时间线中移除。',
              value: timelineController.notShowWatchedBangumis,
              onChanged: (value) {
                timelineController.setNotShowWatchedBangumis(value);
              },
              icon: Icons.task_alt_rounded,
            ),
          ),
          const SizedBox(height: 12),
          Observer(
            builder: (context) => buildFilterOptionTile(
              context,
              title: '只显示在看的番剧',
              description: '聚焦当前正在追更的条目。',
              value: timelineController.onlyShowWatchingBangumis,
              onChanged: (value) {
                timelineController.setOnlyShowWatchingBangumis(value);
              },
              icon: Icons.live_tv_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget showSortSwitcher() {
    return MaterialBottomSheetSection(
      title: '排序方式',
      description: '选择每一天内番剧卡片的排列方式。',
      child: Column(
        children: [
          buildSortOptionTile(
            context,
            sortType: 3,
            title: '按热度排序',
            description: '优先展示讨论度和关注度更高的条目。',
            icon: Icons.local_fire_department_rounded,
          ),
          const SizedBox(height: 12),
          buildSortOptionTile(
            context,
            sortType: 2,
            title: '按评分排序',
            description: '优先展示评分更高的条目。',
            icon: Icons.star_rounded,
          ),
          const SizedBox(height: 12),
          buildSortOptionTile(
            context,
            sortType: 1,
            title: '按时间排序',
            description: '恢复默认时间顺序，方便按播出节奏查看。',
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }

  Widget buildTimelineOptionsSheet(BuildContext context) {
    return buildTimelineBottomSheetShell(
      context,
      header: buildTimelineOptionsSheetHeader(context),
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          showSortSwitcher(),
          const SizedBox(height: 12),
          showFilterSwitcher(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 104,
        bottom: TabBar(
          controller: tabController,
          tabs: tabs,
          indicatorColor: Theme.of(context).colorScheme.primary,
        ),
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          child: Observer(builder: (context) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(timelineController.seasonString),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, size: 20),
              ],
            );
          }),
          onTap: () {
            showSeasonBottomSheet(context);
          },
        ),
        actions: [
          IconButton(
            tooltip: '排序与筛选',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () {
              KazumiDialog.showBottomSheet(
                backgroundColor: Theme.of(context).colorScheme.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                isScrollControlled: true,
                constraints: buildTimelineBottomSheetConstraints(
                  context,
                  compactHeightFactor: 2 / 3,
                ),
                clipBehavior: Clip.antiAlias,
                useSafeArea: true,
                context: context,
                builder: (context) {
                  return buildTimelineOptionsSheet(context);
                },
              );
            },
          ),
        ],
      ),
      body: Observer(builder: (context) {
        if (timelineController.isLoading &&
            timelineController.bangumiCalendar.isEmpty) {
          return const Center(
            child: LoadingIndicator(),
          );
        }
        if (timelineController.isTimeOut) {
          return Center(
            child: SizedBox(
              height: 400,
              child: BangumiMirrorErrorWidget(
                onRetry: () {
                  onSeasonSelected(timelineController.selectedDate);
                },
                onSettingsReturned: () {
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ),
          );
        }
        return TabBarView(
          controller: tabController,
          children: contentGrid(timelineController.bangumiCalendar),
        );
      }),
    );
  }

  // 🆕 Animeko 风格：按天列表条目 + 放送时间 + 今天当前时间指示器
  List<Widget> contentGrid(List<List<BangumiItem>> bangumiCalendar) {
    final todayWeekday = DateTime.now().weekday; // 1-7 周一=1
    final now = DateTime.now();
    final nowStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    List<Widget> listViewList = [];
    for (var dayIdx = 0; dayIdx < 7; dayIdx++) {
      var filteredList = bangumiCalendar[dayIdx];

      if (timelineController.notShowAbandonedBangumis) {
        final abandonedBangumiIds =
            timelineController.loadAbandonedBangumiIds();
        filteredList = filteredList
            .where((item) => !abandonedBangumiIds.contains(item.id))
            .toList();
      }
      if (timelineController.notShowWatchedBangumis) {
        final watchedBangumiIds = timelineController.loadWatchedBangumiIds();
        filteredList = filteredList
            .where((item) => !watchedBangumiIds.contains(item.id))
            .toList();
      }
      if (timelineController.onlyShowWatchingBangumis) {
        final watchingBangumiIds = timelineController.loadWatchingBangumiIds();
        filteredList = filteredList
            .where((item) => watchingBangumiIds.contains(item.id))
            .toList();
      }

      final isToday = (dayIdx + 1) == todayWeekday;
      // 每条目带精确放送时间
      final entries = filteredList
          .map((item) => (item, timelineController.timeOf(item.id)))
          .toList();
      // 天内排序：已知时间升序，时间未定排最后
      entries.sort((a, b) {
        if (a.$2 == null && b.$2 == null) return 0;
        if (a.$2 == null) return 1;
        if (b.$2 == null) return -1;
        return a.$2!.compareTo(b.$2!);
      });

      List<Widget> children = [];
      if (isToday) {
        // 今天：已开播(<=当前) 放前面 → 当前指示器 → 接下来(>当前) → 时间未定
        final passed = entries
            .where((e) => e.$2 != null && e.$2!.compareTo(nowStr) <= 0);
        final upcoming =
            entries.where((e) => e.$2 != null && e.$2!.compareTo(nowStr) > 0);
        final untimed = entries.where((e) => e.$2 == null);
        children = [
          ...passed.map((e) => _buildTimelineItem(e.$1, e.$2, aired: true)),
          _buildCurrentTimeIndicator(nowStr),
          ...upcoming.map((e) => _buildTimelineItem(e.$1, e.$2, aired: false)),
          ...untimed.map((e) => _buildTimelineItem(e.$1, e.$2, aired: false)),
        ];
      } else {
        children =
            entries.map((e) => _buildTimelineItem(e.$1, e.$2, aired: true)).toList();
      }

      listViewList.add(
        CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              sliver: SliverList(
                delegate: SliverChildListDelegate(children),
              ),
            ),
          ],
        ),
      );
    }
    return listViewList;
  }

  /// Animeko 单条目（海报 + 标题 + 放送时刻）
  Widget _buildTimelineItem(BangumiItem item, String? time,
      {required bool aired}) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    final cover = item.images['large'] ??
        item.images['medium'] ??
        item.images['grid'] ??
        '';
    final textColor =
        aired ? colorScheme.onSurface : colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => context.pushNamed('/info/', arguments: item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 66,
                child: cover.isEmpty
                    ? Container(color: colorScheme.surfaceContainerHighest)
                    : Image.network(
                        cover,
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
                    item.airDate.isNotEmpty ? item.airDate : '连载中',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (time != null)
              Text(
                time,
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
                  Text('时间未定',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 当前时间指示器（模仿 Animeko：🔔 + 当前时间 + 分隔线）
  Widget _buildCurrentTimeIndicator(String nowStr) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 0, 10),
            child: Row(
              children: [
                Icon(Icons.alarm_outlined, size: 18, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '现在 $nowStr',
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
            color: colorScheme.primary.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}

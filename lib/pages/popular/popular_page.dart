import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:yhdm/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:yhdm/bean/widget/custom_dropdown_menu.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/widget/last_watch_card.dart';
import 'package:yhdm/modules/history/history_module.dart';
import 'package:yhdm/repositories/history_repository.dart';
import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/pages/popular/popular_controller.dart';
import 'package:yhdm/pages/popular/recommend_section.dart';
import 'package:yhdm/bean/card/bangumi_card.dart';
import 'package:yhdm/utils/constants.dart';
import 'package:yhdm/utils/nsfw_filter.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/announcement/announcement_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yhdm/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:yhdm/utils/device.dart';
import 'package:yhdm/l10n/app_localizations.dart';

class PopularPage extends StatefulWidget {
  const PopularPage({
    super.key,
    required this.controller,
  });

  final PopularController controller;

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage> {
  late final ScrollController scrollController;
  PopularController get popularController => widget.controller;

  // Key used to position the dropdown menu for the tag selector
  final GlobalKey selectorKey = GlobalKey();

  // ===== 上次观看弹窗 =====
  History? _lastHistory;
  bool _showLastWatch = false;
  /// 静态标记：整个应用生命周期只显示一次
  static bool _hasShownLastWatch = false;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
    // 检查上次观看记录
    _checkLastWatch();
  }

  /// 读取最新一条历史记录，用于显示"上次观看"弹窗
  void _checkLastWatch() {
    // 已显示过就不再显示（整个生命周期只一次）
    if (_hasShownLastWatch) return;
    // 检查设置开关
    if (!GStorage.getSetting(SettingsKeys.showLastWatchCard)) return;
    try {
      final historyRepo = HistoryRepository();
      final histories = historyRepo.getAllHistories();
      if (histories.isNotEmpty) {
        final last = histories.first;
        final progress = last.progresses[last.lastWatchEpisode];
        // 有进度且未看完（进度>0）才显示
        if (progress != null && progress.progress > Duration.zero) {
          setState(() {
            _lastHistory = last;
            _showLastWatch = true;
            _hasShownLastWatch = true; // 标记已显示
          });
        }
      }
    } catch (_) {
      // 忽略读取失败
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    super.dispose();
  }

  void scrollListener() {
    popularController.scrollOffset = scrollController.offset;
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 200 &&
        !popularController.isLoadingMore) {
      KazumiLogger()
          .i('PopularPageController: Fetching next recommendation batch');
      if (popularController.currentTag != '') {
        popularController.queryBangumiByTag();
      } else {
        popularController.queryBangumiByTrend();
      }
    }
  }

  bool showWindowButton() {
    return GStorage.getSetting(SettingsKeys.showWindowButton);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              buildSliverAppBar(),
              // 🆕 首页顶部横排「为你推荐」
              const SliverToBoxAdapter(child: RecommendSection()),
              SliverToBoxAdapter(
                child: Observer(
                  builder: (_) => AnimatedOpacity(
                    opacity: popularController.isLoadingMore ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: popularController.isLoadingMore
                        ? const LinearProgressIndicator(minHeight: 4)
                        : const SizedBox(height: 4),
                  ),
                ),
              ),
              SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      StyleString.cardSpace, 0, StyleString.cardSpace, 0),
                  sliver: Observer(builder: (_) {
                    if (popularController.isTimeOut) {
                      return SliverToBoxAdapter(
                        child: SizedBox(
                          height: 400,
                          child: BangumiMirrorErrorWidget(
                            onRetry: () {
                              if (popularController.trendList.isEmpty) {
                                popularController.queryBangumiByTrend();
                              } else {
                                popularController.queryBangumiByTag();
                              }
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
                    return contentGrid(
                      (popularController.currentTag == '')
                          ? popularController.trendList
                          : popularController.bangumiList,
                    );
                  })),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => scrollController.animateTo(0,
                duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
            child: const Icon(Icons.arrow_upward),
          ),
        ),
        // ===== 上次观看弹窗 =====
        if (_showLastWatch && _lastHistory != null)
          Positioned(
            left: 0,
            bottom: 0,
            child: LastWatchCard(
              history: _lastHistory!,
              onDismiss: () {
                if (mounted) {
                  setState(() {
                    _showLastWatch = false;
                  });
                }
              },
            ),
          ),
      ],
    );
  }


  Widget contentGrid(List<BangumiItem> items) {
    final bangumiList = NsfwFilter.filter(items);
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // 行间距
          mainAxisSpacing: StyleString.cardSpace - 2,
          // 列间距
          crossAxisSpacing: StyleString.cardSpace,
          // 列数
          crossAxisCount: crossCount,
          mainAxisExtent:
              MediaQuery.of(context).size.width / crossCount / 0.65 +
                  MediaQuery.textScalerOf(context).scale(32.0),
        ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
            return bangumiList.isNotEmpty
                ? BangumiCardV(bangumiItem: bangumiList[index])
                : null;
          },
          childCount: bangumiList.isNotEmpty ? bangumiList.length : 10,
        ),
      ),
    );
  }

  Widget buildSliverAppBar() {
    final theme = Theme.of(context);
    return SliverAppBar(
      pinned: true,
      expandedHeight: 112,
      elevation: 0,
      titleSpacing: 0,
      centerTitle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      actions: buildActions(),
      title: null,
      flexibleSpace: SafeArea(
        child: dtb.DragToMoveArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double maxExtent = 112 - MediaQuery.of(context).padding.top;
              final t = (1 -
                  ((constraints.maxHeight - kToolbarHeight) /
                          (maxExtent - kToolbarHeight))
                      .clamp(0.0, 1.0));
              // 字重收缩后为 w500，展开时为 w700
              final fontWeight = t < 0.5 ? FontWeight.w700 : FontWeight.w500;
              final fontSize = lerpDouble(28, 20, t)!;
              return Align(
                // 标题贴底，去掉展开态标题下方的垂直留白，让「为你推荐」紧贴热门番组
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2, bottom: 4, right: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 第一行：标题（热门番组/标签选择）
                      SizedBox(
                        height: 40,
                        child: Observer(
                          builder: (_) {
                            final bool isTrend = popularController.currentTag == '';
                            return InkWell(
                              key: selectorKey,
                              borderRadius: BorderRadius.circular(8),
                              onTap: showTagMenu,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isTrend ? AppLocalizations.of(context)!.setHTrending : popularController.currentTag,
                                    style: theme.textTheme.headlineMedium!.copyWith(
                                      fontWeight: fontWeight,
                                      fontSize: fontSize,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.keyboard_arrow_down,
                                      size: fontSize, color: theme.iconTheme.color),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> buildActions() {
    final l10n = AppLocalizations.of(context)!;
    final actions = <Widget>[];
    // 搜索（左）→ 历史（右）→ 活动（最右）
    actions.add(
      IconButton(
        tooltip: l10n.search,
        onPressed: () => context.pushNamed('/search/'),
        icon: const Icon(Icons.search),
      ),
    );
    actions.add(
      IconButton(
        tooltip: l10n.setHHistory,
        onPressed: () => context.pushNamed('/settings/history/'),
        icon: const Icon(Icons.history),
      ),
    );
    // 🆕 活动：点击拉取并展示活动列表
    actions.add(
      IconButton(
        tooltip: '活动',
        onPressed: () => AnnouncementService.openActivities(),
        icon: const Icon(Icons.campaign_outlined),
      ),
    );
    if (isDesktop()) {
      if (!showWindowButton()) {
        actions.add(
          IconButton(
            tooltip: l10n.exit,
            onPressed: () => windowManager.close(),
            icon: const Icon(Icons.close),
          ),
        );
      }
    }
    return actions;
  }

  /// 🆕 用户菜单弹窗

  Future<void> showTagMenu() async {
    // Calculate the position of the button manually to position the dropdown menu.
    // Using CustomDropdownMenu instead of PopupMenuButton to avoid flickering issues
    // and to support different font sizes in the button and menu items.
    final RenderBox renderBox =
        selectorKey.currentContext!.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    final selected = await Navigator.push<String>(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return CustomDropdownMenu(
            offset: offset,
            buttonSize: size,
            animation: animation,
            maxWidth: 80,
            items: [
              '',
              ...defaultAnimeTags,
            ],
            itemBuilder: (item) => item.isEmpty ? AppLocalizations.of(context)!.setHTrending : item,
          );
        },
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
      ),
    );

    if (selected == null) return;
    if (selected == '' && popularController.currentTag != '') {
      scrollController.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      popularController.setCurrentTag('');
      popularController.clearBangumiList();
      if (popularController.trendList.isEmpty) {
        await popularController.queryBangumiByTrend();
      }
    } else if (selected != '' && selected != popularController.currentTag) {
      scrollController.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      popularController.setCurrentTag(selected);
      await popularController.queryBangumiByTag(type: 'init');
    }
  }
}

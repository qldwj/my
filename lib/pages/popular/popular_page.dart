import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/custom_dropdown_menu.dart';
import 'package:kazumi/bean/widget/last_watch_card.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/nsfw_filter.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/models/top_item.dart'; // 导入新模型

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
  late final ScrollController topScrollController; // 热门推荐的滚动控制器
  Timer? _autoScrollTimer;
  
  PopularController get popularController => widget.controller;

  final GlobalKey selectorKey = GlobalKey();

  History? _lastHistory;
  bool _showLastWatch = false;
  static bool _hasShownLastWatch = false;

  @override
  void initState() {
    super.initState();
    
    // 主滚动控制器
    scrollController = ScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    
    // 热门推荐滚动控制器
    topScrollController = ScrollController();
    topScrollController.addListener(_topScrollListener);
    
    // 加载数据
    if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
    
    // 加载热门推荐
    popularController.queryTopItems();
    
    // 启动自动滚动
    _startAutoScroll();
    
    // 检查上次观看记录
    _checkLastWatch();
  }

  void _checkLastWatch() {
    if (_hasShownLastWatch) return;
    if (!GStorage.getSetting(SettingsKeys.showLastWatchCard)) return;
    try {
      final historyRepo = HistoryRepository();
      final histories = historyRepo.getAllHistories();
      if (histories.isNotEmpty) {
        final last = histories.first;
        final progress = last.progresses[last.lastWatchEpisode];
        if (progress != null && progress.progress > Duration.zero) {
          setState(() {
            _lastHistory = last;
            _showLastWatch = true;
            _hasShownLastWatch = true;
          });
        }
      }
    } catch (_) {}
  }

  // 热门推荐滚动监听
  void _topScrollListener() {
    if (topScrollController.position.pixels >= 
        topScrollController.position.maxScrollExtent - 100) {
      popularController.loadMoreTopItems();
    }
  }

  // 自动滚动逻辑
  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      if (!mounted || !topScrollController.hasClients) return;
      if (popularController.topList.isEmpty) return;
      
      final maxScroll = topScrollController.position.maxScrollExtent;
      final currentScroll = topScrollController.position.pixels;
      
      if (currentScroll >= maxScroll - 50) {
        // 到达末尾，回到开头
        topScrollController.animateTo(
          0,
          duration: Duration(seconds: 1),
          curve: Curves.easeInOut,
        );
      } else {
        // 继续向右滚动
        final nextScroll = currentScroll + 160; // 滚动一个卡片的宽度
        topScrollController.animateTo(
          nextScroll.clamp(0.0, maxScroll),
          duration: Duration(seconds: 1),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    topScrollController.dispose();
    super.dispose();
  }

  void scrollListener() {
    popularController.scrollOffset = scrollController.offset;
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 200 &&
        !popularController.isLoadingMore) {
      KazumiLogger().i('PopularPageController: Fetching next recommendation batch');
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
              
              // ===== 新增：热门推荐区域 =====
              SliverToBoxAdapter(
                child: Observer(
                  builder: (_) => _buildTopSection(),
                ),
              ),
              
              // 加载指示器
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
              
              // 原有的番组网格
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
                }),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => scrollController.animateTo(0,
                duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
            child: const Icon(Icons.arrow_upward),
          ),
        ),
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

  // ===== 构建热门推荐区域 =====
  Widget _buildTopSection() {
    if (popularController.isLoadingTop.value) {
      return Container(
        height: 200,
        padding: EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('加载热门推荐...'),
            ],
          ),
        ),
      );
    }

    if (popularController.topList.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text(
                '热门推荐',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              Text(
                '点击卡片查看详情',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            controller: topScrollController,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 12),
            itemCount: popularController.topList.length + 
                (popularController.isTopLoadingMore.value ? 1 : 0),
            itemBuilder: (context, index) {
              // 加载更多指示器
              if (index == popularController.topList.length) {
                return Container(
                  width: 60,
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(),
                );
              }
              
              final item = popularController.topList[index];
              return _buildTopCard(item);
            },
          ),
        ),
        SizedBox(height: 8),
      ],
    );
  }

  // ===== 热门推荐卡片 =====
  Widget _buildTopCard(TopItem item) {
    return GestureDetector(
      onTap: () {
        // 跳转到详情页（根据你的路由调整）
        // 例如：context.pushNamed('/bangumi/detail/${item.id}');
        print('点击了: ${item.nameCn}');
        // 这里可以添加跳转逻辑
      },
      child: Container(
        width: 140,
        margin: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 封面图
              Image.network(
                item.image,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.grey[300],
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: Icon(Icons.error, color: Colors.grey[600]),
                  );
                },
              ),
              // 渐变底部
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
              ),
              // 底部信息
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.nameCn.isNotEmpty ? item.nameCn : item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      if (item.rating > 0)
                        Row(
                          children: [
                            Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 12,
                            ),
                            SizedBox(width: 2),
                            Text(
                              item.rating.toString(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              // 评分角标
              if (item.rating > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.rating.toString(),
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
          mainAxisSpacing: StyleString.cardSpace - 2,
          crossAxisSpacing: StyleString.cardSpace,
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
      stretch: true,
      expandedHeight: 120,
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
              final double maxExtent = 120 - MediaQuery.of(context).padding.top;
              final t = (1 -
                  ((constraints.maxHeight - kToolbarHeight) /
                          (maxExtent - kToolbarHeight))
                      .clamp(0.0, 1.0));
              final fontWeight = t < 0.5 ? FontWeight.w700 : FontWeight.w500;
              final fontSize = lerpDouble(28, 20, t)!;
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                      left: 16, top: 8, bottom: 8, right: 60),
                  child: SizedBox(
                    height: 44,
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
                                isTrend ? '热门番组' : popularController.currentTag,
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> buildActions() {
    final actions = <Widget>[
      if (MediaQuery.of(context).orientation == Orientation.portrait)
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.pushNamed('/search/'),
          icon: const Icon(Icons.search),
        ),
    ];
    actions.add(
      IconButton(
        tooltip: '历史记录',
        onPressed: () => context.pushNamed('/settings/history/'),
        icon: const Icon(Icons.history),
      ),
    );
    if (isDesktop()) {
      if (!showWindowButton()) {
        actions.add(
          IconButton(
            tooltip: '退出',
            onPressed: () => windowManager.close(),
            icon: const Icon(Icons.close),
          ),
        );
      }
    }
    return actions;
  }

  Future<void> showTagMenu() async {
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
            itemBuilder: (item) => item.isEmpty ? '热门番组' : item,
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
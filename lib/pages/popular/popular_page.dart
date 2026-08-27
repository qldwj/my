import 'dart:ui';
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
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/pages/my/kazumi_login_page.dart';
import 'package:kazumi/pages/my/profile_edit_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/utils/device.dart';

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
              // 字重收缩后为 w500，展开时为 w700
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
    final isLoggedIn = AuthService.isLoggedIn;
    final actions = <Widget>[
      if (MediaQuery.of(context).orientation == Orientation.portrait)
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.pushNamed('/search/'),
          icon: const Icon(Icons.search),
        ),
    ];
    // 🆕 已登录显示头像，未登录显示登录图标
    actions.add(
      IconButton(
        tooltip: isLoggedIn ? '个人中心' : '登录',
        onPressed: () => _showUserMenu(context),
        icon: isLoggedIn
            ? FutureBuilder<SocialProfile?>(
                future: SocialService.getProfile(),
                builder: (ctx, snap) {
                  final profile = snap.data;
                  if (profile != null && profile.avatar.isNotEmpty) {
                    return CircleAvatar(
                      radius: 14,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: ClipOval(
                        child: NetworkImgLayer(
                          width: 28, height: 28,
                          src: SocialService.proxiedAvatar(profile.avatar),
                        ),
                      ),
                    );
                  }
                  return const Icon(Icons.account_circle, size: 28);
                },
              )
            : const Icon(Icons.account_circle_outlined),
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

  /// 🆕 用户菜单弹窗
  void _showUserMenu(BuildContext context) {
    final isLoggedIn = AuthService.isLoggedIn;
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return FutureBuilder<SocialProfile?>(
          future: SocialService.getProfile(),
          builder: (ctx, snap) {
            final profile = snap.data;
            final displayName = profile?.nickname ?? (isLoggedIn ? '樱花动漫用户' : '未登录');
            final avatar = profile?.avatar ?? '';

            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 头像
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: cs.primaryContainer,
                    child: avatar.isNotEmpty
                        ? ClipOval(
                            child: NetworkImgLayer(
                              width: 72, height: 72,
                              src: SocialService.proxiedAvatar(avatar),
                            ),
                          )
                        : Icon(
                            isLoggedIn ? Icons.account_circle : Icons.account_circle_outlined,
                            size: 48, color: cs.primary,
                          ),
                  ),
                  const SizedBox(height: 12),
                  Text(displayName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  if (isLoggedIn) ...[
                    _menuTile(ctx, Icons.edit, '编辑个人资料', () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ProfileEditPage()));
                    }),
                    _menuTile(ctx, Icons.history, '播放历史', () {
                      Navigator.pop(ctx);
                      context.pushNamed('/settings/history/');
                    }),
                    _menuTile(ctx, Icons.settings, '设置', () {
                      Navigator.pop(ctx);
                      context.pushNamed('/settings/');
                    }),
                    _menuTile(ctx, Icons.logout, '退出登录', () async {
                      Navigator.pop(ctx);
                      final confirm = await KazumiDialog.show<bool>(
                        builder: (c) => AlertDialog(
                          title: const Text('退出登录'),
                          content: const Text('确定退出登录吗？'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                            TextButton(onPressed: () => Navigator.pop(c, true),
                              child: Text('确定', style: TextStyle(color: cs.error))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        AuthService.clearLocalToken();
                        SocialService.clearProfileCache();
                        setState(() {});
                      }
                    }),
                  ] else ...[
                    _menuTile(ctx, Icons.login, '注册 / 登录', () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const KazumiLoginPage()));
                    }),
                    _menuTile(ctx, Icons.history, '播放历史', () {
                      Navigator.pop(ctx);
                      context.pushNamed('/settings/history/');
                    }),
                    _menuTile(ctx, Icons.settings, '设置', () {
                      Navigator.pop(ctx);
                      context.pushNamed('/settings/');
                    }),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _menuTile(BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

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

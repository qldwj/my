import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/card/comments_card.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/card/character_card.dart';
import 'package:kazumi/bean/card/staff_card.dart';
import 'package:kazumi/bean/widget/recommendation_section.dart';
import 'package:kazumi/bean/widget/related_anime_section.dart';
import 'package:kazumi/bean/widget/related_search_section.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/services/social/admin_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/modules/characters/character_item.dart';
import 'package:kazumi/modules/staff/staff_item.dart';
import 'package:kazumi/utils/device.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

class InfoTabView extends StatefulWidget {
  const InfoTabView({
    super.key,
    required this.commentsQueryTimeout,
    required this.commentsIsEmpty,
    required this.charactersQueryTimeout,
    required this.charactersIsEmpty,
    required this.staffQueryTimeout,
    required this.staffIsEmpty,
    required this.tabController,
    required this.loadMoreComments,
    required this.loadCharacters,
    required this.loadStaff,
    required this.bangumiItem,
    required this.commentsList,
    required this.commentsIsLoading,
    this.onCommentsTabSelected,
    this.onPublishComment,
    this.onRefreshComments,
    required this.characterList,
    required this.staffList,
    required this.isLoading,
  });

  final bool commentsQueryTimeout;
  final bool commentsIsEmpty;
  final bool commentsIsLoading;
  final VoidCallback? onCommentsTabSelected;
  final VoidCallback? onRefreshComments;
  final Future<String?> Function(String text, int rating)? onPublishComment;
  final bool charactersQueryTimeout;
  final bool charactersIsEmpty;
  final bool staffQueryTimeout;
  final bool staffIsEmpty;
  final TabController tabController;
  final Future<void> Function({bool loadMore}) loadMoreComments;
  final Future<void> Function() loadCharacters;
  final Future<void> Function() loadStaff;
  final BangumiItem bangumiItem;
  final List<CommentItem> commentsList;
  final List<CharacterItem> characterList;
  final List<StaffFullItem> staffList;
  final bool isLoading;

  @override
  State<InfoTabView> createState() => _InfoTabViewState();
}

class _InfoTabViewState extends State<InfoTabView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _commentController = TextEditingController();
  int _commentRating = 0;
  bool _commentSending = false;
  final maxWidth = 950.0;
  bool fullIntro = false;
  bool fullTag = false;

  // 🆕 缓存管理员状态
  ({bool admin, String headTitle, String uid})? _adminCache;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onTabChanged);
    if (widget.tabController.index == 1) {
      widget.onCommentsTabSelected?.call();
    }
    // 🆕 预加载管理员状态
    _loadAdminStatus();
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.tabController.index == 1) {
      widget.onCommentsTabSelected?.call();
    }
  }

  /// 🆕 加载管理员状态
  Future<void> _loadAdminStatus() async {
    try {
      final admin = await AdminService.me(refresh: true);
      if (mounted) {
        setState(() {
          _adminCache = admin;
        });
      }
    } catch (e) {
      // 忽略
    }
  }

  /// 🆕 刷新管理员状态
  Future<void> _refreshAdminStatus() async {
    try {
      final admin = await AdminService.me(refresh: true);
      if (mounted) {
        setState(() {
          _adminCache = admin;
        });
      }
    } catch (e) {
      // 忽略
    }
  }

  Widget get infoBody {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width > maxWidth
              ? maxWidth
              : MediaQuery.sizeOf(context).width - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('简介', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, constraints) {
                final span = TextSpan(text: widget.bangumiItem.summary);
                final tp =
                    TextPainter(text: span, textDirection: TextDirection.ltr);
                tp.layout(maxWidth: constraints.maxWidth);
                final numLines = tp.computeLineMetrics().length;
                if (numLines > 7) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: fullIntro ? null : 120,
                        width: MediaQuery.sizeOf(context).width > maxWidth
                            ? maxWidth
                            : MediaQuery.sizeOf(context).width - 32,
                        child: SelectableText(
                          widget.bangumiItem.summary,
                          textAlign: TextAlign.start,
                          scrollBehavior: const ScrollBehavior().copyWith(
                            scrollbars: false,
                          ),
                          scrollPhysics: NeverScrollableScrollPhysics(),
                          selectionHeightStyle: ui.BoxHeightStyle.max,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            fullIntro = !fullIntro;
                          });
                        },
                        child: Text(fullIntro ? '加载更少' : '加载更多'),
                      ),
                    ],
                  );
                } else {
                  return SelectableText(
                    widget.bangumiItem.summary,
                    textAlign: TextAlign.start,
                    scrollPhysics: NeverScrollableScrollPhysics(),
                    selectionHeightStyle: ui.BoxHeightStyle.max,
                  );
                }
              }),
              const SizedBox(height: 16),
              Text('标签', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: isDesktop() ? 8 : 0,
                children: List<Widget>.generate(
                    fullTag || widget.bangumiItem.tags.length < 13
                        ? widget.bangumiItem.tags.length
                        : 13, (int index) {
                  if (!fullTag && index == 12) {
                    return ActionChip(
                      label: Text(
                        '更多 +',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                      onPressed: () {
                        setState(() {
                          fullTag = !fullTag;
                        });
                      },
                    );
                  }
                  return ActionChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${widget.bangumiItem.tags[index].name} '),
                        Text(
                          '${widget.bangumiItem.tags[index].count}',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                    ),
                    onPressed: () {
                      final tagName = Uri.encodeComponent(
                          widget.bangumiItem.tags[index].name);
                      context.pushNamed('/search/$tagName');
                    },
                  );
                }).toList(),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget get infoBodyBone {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width > maxWidth
              ? maxWidth
              : MediaQuery.sizeOf(context).width - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeletonizer.zone(child: Bone.text(fontSize: 18, width: 50)),
              const SizedBox(height: 8),
              Skeletonizer.zone(child: Bone.multiText(lines: 7)),
              const SizedBox(height: 16),
              Skeletonizer.zone(child: Bone.text(fontSize: 18, width: 50)),
              const SizedBox(height: 8),
              if (widget.isLoading)
                Skeletonizer.zone(
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: List.generate(
                        4, (_) => Bone.button(uniRadius: 8, height: 32)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentInput() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            IconButton(
              tooltip: _commentRating > 0
                  ? '已评 $_commentRating 分，点击修改'
                  : '给这部番打分（0-10）',
              onPressed: _pickCommentRating,
              icon: Icon(
                _commentRating > 0
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: _commentRating > 0 ? Colors.amber : null,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _commentController,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '发一条评论…（樱花服务器）',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _commentSending ? null : _publishComment,
              icon: const Icon(Icons.send_rounded),
              tooltip: '发表',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCommentRating() async {
    var value = _commentRating.toDouble();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('给这部番打分'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value <= 0 ? '未评分' : '${value.round()} 分',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              RatingBar.builder(
                initialRating: value,
                minRating: 0,
                maxRating: 10,
                itemCount: 10,
                itemSize: 28,
                allowHalfRating: false,
                onRatingUpdate: (v) {
                  value = v;
                  setDialogState(() {});
                },
                itemBuilder: (context, index) => const Icon(
                  Icons.star_rounded,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0.0),
            child: Text('取消评分',
                style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, value),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() => _commentRating = result.round().clamp(0, 10));
    }
  }

  /// 🆕 管理员长按评论菜单（完全重写，只检查管理员，不检查评论归属）
  Future<void> _showCommentAdminMenu(
      BuildContext context, CommentItem item) async {
    // 🆕 先刷新管理员状态
    await _refreshAdminStatus();
    
    // 🆕 检查是否是管理员
    final admin = _adminCache;
    if (admin == null || !admin.admin) {
      KazumiDialog.showToast(message: '您不是管理员，无法操作');
      return;
    }

    // 🆕 获取当前用户 uid
    final myUid = SocialService.restoreLocalProfile()?.uid ?? '';
    final isOwnComment = item.uid.isNotEmpty && item.uid == myUid;

    // 🆕 构建菜单项
    final List<({String title, String action, IconData icon, bool danger})> menuItems = [];

    // 只有自己发布的评论才能置顶
    if (isOwnComment) {
      menuItems.add((
        title: item.pinned ? '取消置顶' : '置顶评论',
        action: 'pin',
        icon: item.pinned ? Icons.vertical_align_top_rounded : Icons.push_pin_outlined,
        danger: false,
      ));
    }

    // 修改头衔（所有管理员都可以）
    menuItems.add((
      title: '修改我的头衔',
      action: 'title',
      icon: Icons.badge_outlined,
      danger: false,
    ));

    // 🆕 查看禁言列表（所有管理员都可以）
    menuItems.add((
      title: '查看禁言列表',
      action: 'mute_list',
      icon: Icons.list_alt,
      danger: false,
    ));

    // 🆕 禁言用户（所有管理员都可以）
    if (item.uid.isNotEmpty && item.uid != myUid) {
      menuItems.add((
        title: '禁言用户',
        action: 'mute',
        icon: Icons.block,
        danger: true,
      ));
    }

    if (menuItems.isEmpty) {
      KazumiDialog.showToast(message: '没有可用的操作');
      return;
    }

    if (!context.mounted) return;

    // 🆕 显示菜单
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...menuItems.map((menu) => ListTile(
                  leading: Icon(
                    menu.icon,
                    color: menu.danger ? Colors.red : null,
                  ),
                  title: Text(
                    menu.title,
                    style: TextStyle(
                      color: menu.danger ? Colors.red : null,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, menu.action),
                )),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;

    // 🆕 处理菜单操作
    switch (action) {
      case 'pin':
        final error = await AdminService.pinSelf(item.user.id.abs(), pinned: !item.pinned);
        if (!mounted) return;
        KazumiDialog.showToast(
          message: error == null 
              ? '✅ 已${item.pinned ? '取消置顶' : '置顶'}' 
              : '❌ $error'
        );
        widget.onRefreshComments?.call();
        break;

      case 'title':
        await _showSetTitleDialog(context);
        break;

      case 'mute_list':
        await _showMuteListDialog(context);
        break;

      case 'mute':
        await _showMuteUserDialog(context, item.uid);
        break;
    }
  }

  /// 🆕 修改头衔弹窗
  Future<void> _showSetTitleDialog(BuildContext context) async {
    final admin = _adminCache;
    if (admin == null) return;

    final controller = TextEditingController(text: admin.headTitle);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改我的头衔'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '如：官方小编'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty || !mounted) return;
    final error = await AdminService.setTitle(title.trim());
    if (!mounted) return;
    KazumiDialog.showToast(
        message: error == null ? '✅ 头衔已更新为「${title.trim()}」' : '❌ $error');
    await _refreshAdminStatus();
    widget.onRefreshComments?.call();
  }

  /// 🆕 禁言用户弹窗
  Future<void> _showMuteUserDialog(BuildContext context, String uid) async {
    int duration = 3600;
    String reason = '';
    bool isPermanent = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('禁言用户'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('用户 UID: $uid', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: duration,
                decoration: const InputDecoration(
                  labelText: '禁言时长',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 600, child: Text('10分钟')),
                  DropdownMenuItem(value: 1800, child: Text('30分钟')),
                  DropdownMenuItem(value: 3600, child: Text('1小时')),
                  DropdownMenuItem(value: 86400, child: Text('1天')),
                  DropdownMenuItem(value: 604800, child: Text('7天')),
                  DropdownMenuItem(value: 0, child: Text('永久')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    duration = value;
                    isPermanent = value == 0;
                    setDialogState(() {});
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: '禁言原因（可选）',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                onChanged: (value) => reason = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认禁言'),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final error = await AdminService.muteUser(
      uid: int.tryParse(uid) ?? 0,
      duration: duration,
      reason: reason,
    );
    if (!mounted) return;
    KazumiDialog.showToast(
      message: error == null ? '✅ 用户已被禁言' : '❌ $error',
    );
  }

  /// 🆕 查看禁言列表
  Future<void> _showMuteListDialog(BuildContext context) async {
    final list = await AdminService.getMuteList(refresh: true);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            const Text('禁言列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('暂无禁言用户'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: list.length,
                      itemBuilder: (ctx, index) {
                        final user = list[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: user.avatar.isNotEmpty
                                ? Image.network(user.avatar)
                                : Text(user.nickname[0]),
                          ),
                          title: Text(user.nickname),
                          subtitle: Text(
                            'UID: ${user.uid}\n'
                            '原因: ${user.reason.isNotEmpty ? user.reason : "无"}\n'
                            '剩余: ${user.remainingTime}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: user.isExpired
                              ? const Chip(label: Text('已过期'), backgroundColor: Colors.grey)
                              : IconButton(
                                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: ctx,
                                      builder: (ctx2) => AlertDialog(
                                        title: const Text('解禁用户'),
                                        content: Text('确定要解禁 ${user.nickname} 吗？'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx2, false),
                                            child: const Text('取消'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(ctx2, true),
                                            child: const Text('解禁'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      final error = await AdminService.unmuteUser(user.uid);
                                      if (!ctx.mounted) return;
                                      if (error == null) {
                                        KazumiDialog.showToast(message: '✅ 已解禁');
                                        Navigator.pop(ctx);
                                        _showMuteListDialog(context);
                                      } else {
                                        KazumiDialog.showToast(message: '❌ $error');
                                      }
                                    }
                                  },
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publishComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _commentSending) return;
    final publish = widget.onPublishComment;
    if (publish == null) return;
    setState(() => _commentSending = true);
    final error = await publish(text, _commentRating);
    if (!mounted) return;
    setState(() => _commentSending = false);
    if (error == null) {
      _commentController.clear();
      setState(() => _commentRating = 0);
      KazumiDialog.showToast(message: '评论已发布 ✅');
    }
  }

  Widget get commentsListBody {
    return Builder(
      builder: (BuildContext context) {
        return NotificationListener<ScrollEndNotification>(
          onNotification: (scrollEnd) {
            final metrics = scrollEnd.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 200) {
              widget.loadMoreComments(loadMore: widget.commentsList.isNotEmpty);
            }
            return true;
          },
          child: CustomScrollView(
            scrollBehavior: const ScrollBehavior().copyWith(
              scrollbars: false,
            ),
            key: PageStorageKey<String>('吐槽'),
            slivers: <Widget>[
              SliverOverlapInjector(
                handle:
                    NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              ),
              if (widget.onPublishComment != null)
                SliverToBoxAdapter(child: _buildCommentInput()),
              SliverLayoutBuilder(builder: (context, _) {
                final myInterest = widget.bangumiItem.interest;
                final showMyReview = !widget.commentsIsLoading &&
                    myInterest != null &&
                    myInterest.hasUserProfile &&
                    myInterest.hasReviewContent;
                final listItemCount =
                    widget.commentsList.length + (showMyReview ? 1 : 0);

                if (listItemCount > 0) {
                  return SliverList.separated(
                    addAutomaticKeepAlives: false,
                    itemCount: listItemCount,
                    itemBuilder: (context, index) {
                      final commentIndex = showMyReview ? index - 1 : index;
                      final myUser = myInterest?.user;
                      final card = showMyReview && index == 0 && myUser != null
                          ? CommentsCard.own(
                              commentItem: CommentItem(
                                user: myUser,
                                comment: Comment(
                                  rate: myInterest.rate,
                                  comment: myInterest.comment,
                                  updatedAt: myInterest.updatedAt,
                                ),
                              ),
                            )
                          : CommentsCard(
                              commentItem: widget.commentsList[commentIndex],
                            );
                      final isServer = commentIndex >= 0 && 
                          commentIndex < widget.commentsList.length &&
                          widget.commentsList[commentIndex].source == 'server';
                      return SafeArea(
                        top: false,
                        bottom: false,
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: SizedBox(
                              width: MediaQuery.sizeOf(context).width > maxWidth
                                  ? maxWidth
                                  : MediaQuery.sizeOf(context).width - 32,
                              child: GestureDetector(
                                onLongPress: () async {
                                  if (commentIndex >= 0 && 
                                      commentIndex < widget.commentsList.length) {
                                    await _showCommentAdminMenu(
                                      context,
                                      widget.commentsList[commentIndex],
                                    );
                                  }
                                },
                                child: card,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (BuildContext context, int index) {
                      return SafeArea(
                        top: false,
                        bottom: false,
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: SizedBox(
                              width: MediaQuery.sizeOf(context).width > maxWidth
                                  ? maxWidth
                                  : MediaQuery.sizeOf(context).width - 32,
                              child: Divider(
                                  thickness: 0.5, indent: 10, endIndent: 10),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
                if (widget.commentsQueryTimeout) {
                  return SliverFillRemaining(
                    child: GeneralErrorWidget(
                      errMsg: '获取失败，请重试',
                      actions: [
                        GeneralErrorButton(
                          onPressed: () {
                            widget.loadMoreComments(
                                loadMore: widget.commentsList.isNotEmpty);
                          },
                          text: '重试',
                        ),
                      ],
                    ),
                  );
                }
                if (widget.commentsIsEmpty) {
                  return const SliverFillRemaining(
                    child: Center(
                      child: Text('什么都没有找到 (´;ω;`)'),
                    ),
                  );
                }
                return SliverList.builder(
                  itemCount: 4,
                  itemBuilder: (context, _) {
                    return SafeArea(
                      top: false,
                      bottom: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: MediaQuery.sizeOf(context).width > maxWidth
                                ? maxWidth
                                : MediaQuery.sizeOf(context).width - 32,
                            child: CommentsCard.bone(),
                          ),
                        ),
                      ),
                    );
                  },
                );
              })
            ],
          ),
        );
      },
    );
  }

  Widget get staffListBody {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          scrollBehavior: const ScrollBehavior().copyWith(
            scrollbars: false,
          ),
          key: PageStorageKey<String>('制作人员'),
          slivers: <Widget>[
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverLayoutBuilder(builder: (context, _) {
              if (widget.staffList.isNotEmpty) {
                return SliverList.builder(
                  itemCount: widget.staffList.length,
                  itemBuilder: (context, index) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: SizedBox(
                          width: MediaQuery.sizeOf(context).width > maxWidth
                              ? maxWidth
                              : MediaQuery.sizeOf(context).width - 32,
                          child: StaffCard(
                            staffFullItem: widget.staffList[index],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }
              if (widget.staffQueryTimeout) {
                return SliverFillRemaining(
                  child: GeneralErrorWidget(
                    errMsg: '获取失败，请重试',
                    actions: [
                      GeneralErrorButton(
                        onPressed: () {
                          widget.loadStaff();
                        },
                        text: '重试',
                      ),
                    ],
                  ),
                );
              }
              if (widget.staffIsEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text('什么都没有找到 (´;ω;`)'),
                  ),
                );
              }
              return SliverList.builder(
                itemCount: 8,
                itemBuilder: (context, _) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: MediaQuery.sizeOf(context).width > maxWidth
                          ? maxWidth
                          : MediaQuery.sizeOf(context).width - 32,
                      child: Skeletonizer.zone(
                        child: ListTile(
                          leading: Bone.circle(size: 36),
                          title: Bone.text(width: 100),
                          subtitle: Bone.text(width: 80),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }

  Widget get charactersListBody {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          scrollBehavior: const ScrollBehavior().copyWith(
            scrollbars: false,
          ),
          key: PageStorageKey<String>('角色'),
          slivers: <Widget>[
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverLayoutBuilder(builder: (context, _) {
              if (widget.characterList.isNotEmpty) {
                return SliverList.builder(
                  itemCount: widget.characterList.length,
                  itemBuilder: (context, index) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: SizedBox(
                          width: MediaQuery.sizeOf(context).width > maxWidth
                              ? maxWidth
                              : MediaQuery.sizeOf(context).width - 32,
                          child: CharacterCard(
                            characterItem: widget.characterList[index],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }
              if (widget.charactersQueryTimeout) {
                return SliverFillRemaining(
                  child: GeneralErrorWidget(
                    errMsg: '获取失败，请重试',
                    actions: [
                      GeneralErrorButton(
                        onPressed: () {
                          widget.loadCharacters();
                        },
                        text: '重试',
                      ),
                    ],
                  ),
                );
              }
              if (widget.charactersIsEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text('什么都没有找到 (´;ω;`)'),
                  ),
                );
              }
              return SliverList.builder(
                itemCount: 4,
                itemBuilder: (context, _) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: MediaQuery.sizeOf(context).width > maxWidth
                          ? maxWidth
                          : MediaQuery.sizeOf(context).width - 32,
                      child: Skeletonizer.zone(
                        child: ListTile(
                          leading: Bone.circle(size: 36),
                          title: Bone.text(width: 100),
                          subtitle: Bone.text(width: 80),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: widget.tabController,
      children: [
        Builder(
          builder: (BuildContext context) {
            return CustomScrollView(
              scrollBehavior: const ScrollBehavior().copyWith(
                scrollbars: false,
              ),
              key: PageStorageKey<String>('概览'),
              slivers: <Widget>[
                SliverOverlapInjector(
                  handle:
                      NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                ),
                SliverToBoxAdapter(
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: widget.isLoading ? infoBodyBone : infoBody,
                  ),
                ),
                SliverToBoxAdapter(
                  child: RecommendationSection(
                    currentBangumi: widget.bangumiItem,
                  ),
                ),
                SliverToBoxAdapter(
                  child: RelatedAnimeSection(
                    currentBangumi: widget.bangumiItem,
                  ),
                ),
              ],
            );
          },
        ),
        commentsListBody,
        charactersListBody,
        Builder(
          builder: (BuildContext context) {
            return RelatedSearchSection(
              currentBangumi: widget.bangumiItem,
            );
          },
        ),
        staffListBody,
      ],
    );
  }
}
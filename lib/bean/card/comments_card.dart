import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:kazumi/utils/date_time.dart';
import 'package:kazumi/request/apis/custom_comment_api.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:url_launcher/url_launcher.dart';

class CommentsCard extends StatelessWidget {
  CommentsCard({
    super.key,
    required this.commentItem,
  }) {
    isBone = false;
    isOwn = false;
  }

  CommentsCard.bone({
    super.key,
  }) {
    isBone = true;
    commentItem = null;
    isOwn = false;
  }

  CommentsCard.own({
    super.key,
    required this.commentItem,
  }) {
    isBone = false;
    isOwn = true;
  }

  late final CommentItem? commentItem;
  late final bool isBone;
  late final bool isOwn;

  @override
  Widget build(BuildContext context) {
    if (isBone) {
      return Skeletonizer.zone(
        enabled: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Bone.circle(size: 36),
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Bone.text(width: 80),
                    SizedBox(height: 8),
                    Bone.text(width: 60),
                  ],
                ),
              ],
            ),
            SizedBox(height: 8),
            const Bone.multiText(lines: 2),
            Divider(thickness: 0.5, indent: 10, endIndent: 10),
          ],
        ),
      );
    }
    final item = commentItem!;
    final cs = Theme.of(context).colorScheme;
    final showTitle = item.title.isNotEmpty;
    final isHot = item.source == 'server' && item.votes >= 5;
    return GestureDetector(
      onLongPress: item.source == 'server' ? _reportComment : null,
      child: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 头像：点击跳个人主页
                  GestureDetector(
                    onTap: _openProfile,
                    child: BangumiAvatar(
                      url: item.user.avatar.large,
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 昵称 + 称号 + 我的吐槽
                        Row(
                          spacing: 5,
                          children: [
                            Text(item.user.nickname,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            if (showTitle)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3E8FF),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  item.title,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF7B3FF2)),
                                ),
                              ),
                            if (isOwn)
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('我的吐槽',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.primaryContainer)),
                              ),
                          ],
                        ),
                        // 时间 + 来源 + 置顶 + 热门（小标签行）
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(dateFormat(item.comment.updatedAt),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant)),
                            // 来源标签
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: item.source == 'server'
                                    ? cs.primaryContainer
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.source == 'server' ? '樱花' : 'Bangumi',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: item.source == 'server'
                                      ? cs.onPrimaryContainer
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            // 置顶标签
                            if (item.pinned)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('📌 置顶',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFE65100))),
                              ),
                            // 热门标签
                            if (isHot)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('🔥 热门',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFC62828))),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // 评分星星 + 积分（独立一行，不挤不溢）
              const SizedBox(height: 8),
              Row(
                children: [
                  RatingBarIndicator(
                    itemCount: 5,
                    rating: item.comment.rate.toDouble() / 2,
                    itemBuilder: (context, index) => const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFB300),
                    ),
                    itemSize: 18.0,
                  ),
                  const Spacer(),
                  if (item.coins > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '💰 ${item.coins} 积分',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF1565C0)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(item.comment.comment),
            ],
          ),
        ),
      ),
    );
  }

  /// 🆕 点击头像 → 打开个人主页（yhdm://u/{uid} 深链）
  void _openProfile() {
    final uid = commentItem?.uid ?? '';
    if (uid.isEmpty) return;
    launchUrl(Uri.parse('yhdm://u/$uid'));
  }

  /// 🆕 长按评论 → 举报（樱花评论）
  Future<void> _reportComment() async {
    final item = commentItem!;
    if (item.source != 'server') return;
    final reasons = ['低俗色情', '广告引流', '辱骂攻击', '其他违规'];
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('举报这条评论'),
        children: [
          for (final r in reasons)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Text(r),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (res == null) return;
    // server 评论的本地 id = -c.id（负数），绝对值即服务端 id
    final err = await CustomCommentApi.report(
        commentId: item.user.id.abs(), reason: res);
    if (err == null) {
      KazumiDialog.showToast(message: '举报成功，感谢反馈');
    } else {
      KazumiDialog.showToast(message: err);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:yhdm/models/episode_comment.dart';
import 'package:yhdm/widgets/comment/bgm_rich_text.dart';
import 'package:yhdm/bean/widget/bangumi_avatar.dart';

/// 评论卡片（仅 Bangumi，只读）
///
/// - 头像：BangumiAvatar（走图片代理，能显示真实头像）
/// - 昵称 + 称号徽章 + 时间
/// - 来源标签：固定 Bangumi
/// - 评论内容：BgmRichText（支持 BBCode/表情）
/// - 回复列表：可展开查看（只读）
///
/// 已移除樱花动漫评论相关的一切交互（点赞/点踩/贴纸/举报/删除/回复输入）。
class CommentItemWidget extends StatefulWidget {
  final EpisodeComment comment;
  final int subjectId;
  final Function()? onRefresh;
  const CommentItemWidget(
      {super.key, required this.comment, required this.subjectId, this.onRefresh});
  @override
  State<CommentItemWidget> createState() => _CommentItemWidgetState();
}

class _CommentItemWidgetState extends State<CommentItemWidget> {
  bool _showReplies = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: cs.surfaceContainerLow,
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：头像 + 昵称 + 来源标签 + 时间
            Row(children: [
              c.avatar.isNotEmpty
                  ? ClipOval(child: BangumiAvatar(url: c.avatar, size: 32))
                  : CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.orange.shade100,
                      child: Text(
                        c.sender.isNotEmpty ? c.sender[0].toUpperCase() : '?',
                        style:
                            const TextStyle(fontSize: 14, color: Colors.orange),
                      ),
                    ),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(c.sender,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    // 称号徽章（已解锁自选称号）
                    if (c.title.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(5)),
                        child: Text(c.title,
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF7B3FF2))),
                      ),
                    ],
                  ]),
                  Text(c.timeAgo,
                      style: TextStyle(fontSize: 11, color: cs.outline)),
                ],
              )),
              // 来源标签：固定 Bangumi
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Bangumi',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 8),
            // 评论内容
            BgmRichText(c.content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: cs.onSurface,
                )),
            // 展开回复（只读）
            if (c.replies.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => _showReplies = !_showReplies),
                child: Text(
                    _showReplies ? '收起回复' : '展开${c.replies.length}条回复',
                    style: TextStyle(fontSize: 12, color: cs.primary)),
              ),
            ],
            // 回复列表
            if (_showReplies && c.replies.isNotEmpty) ...[
              const Divider(height: 16),
              ...c.replies.map((r) => Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(r.sender,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(width: 6),
                          const Text('Bangumi',
                              style: TextStyle(
                                  fontSize: 9, color: Colors.orange)),
                          const SizedBox(width: 6),
                          Text(r.timeAgo,
                              style: TextStyle(fontSize: 10, color: cs.outline)),
                        ]),
                        const SizedBox(height: 4),
                        BgmRichText(r.content,
                            style:
                                TextStyle(fontSize: 13, color: cs.onSurface)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

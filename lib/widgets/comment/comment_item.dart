import 'package:flutter/material.dart';
import 'package:kazumi/models/episode_comment.dart';
import 'package:kazumi/services/comment/episode_comment_service.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/pages/my/profile_page.dart';
import 'package:kazumi/widgets/comment/bgm_rich_text.dart';

class CommentItemWidget extends StatefulWidget {
  final EpisodeComment comment;
  final int subjectId;
  final Function()? onRefresh;
  const CommentItemWidget({super.key, required this.comment, required this.subjectId, this.onRefresh});
  @override
  State<CommentItemWidget> createState() => _CommentItemWidgetState();
}

class _CommentItemWidgetState extends State<CommentItemWidget> {
  bool _showReplies = false;
  final _replyController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: cs.surface, // 🆕 不透明背景，避免透出粉色背景看不清文字
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：头像 + 昵称 + 来源标签 + 时间
            Row(children: [
              GestureDetector(
                onTap: () {
                  // 🆕 点击头像查看个人主页（仅樱花评论有 uid）
                  if (c.isSakura && c.uid.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfilePage(
                          uid: c.uid,
                          nickname: c.sender,
                          avatar: c.avatar,
                        ),
                      ),
                    );
                  }
                },
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: c.isSakura ? cs.primaryContainer : Colors.orange.shade100,
                  child: c.avatar.isNotEmpty && c.isSakura
                      ? ClipOval(
                          child: Image.network(
                            SocialService.proxiedAvatar(c.avatar),
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              c.sender.isNotEmpty ? c.sender[0].toUpperCase() : '?',
                              style: TextStyle(fontSize: 14, color: c.isSakura ? cs.primary : Colors.orange),
                            ),
                          ),
                        )
                      : Text(c.sender.isNotEmpty ? c.sender[0].toUpperCase() : '?',
                          style: TextStyle(fontSize: 14, color: c.isSakura ? cs.primary : Colors.orange)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.sender, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(c.timeAgo, style: TextStyle(fontSize: 11, color: cs.outline)),
                ],
              )),
              // 来源标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.isSakura ? cs.primary.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(c.isSakura ? '樱花动漫' : 'Bangumi',
                  style: TextStyle(fontSize: 10, color: c.isSakura ? cs.primary : Colors.orange, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 8),
            // 评论内容
            BgmRichText(c.content, style: const TextStyle(fontSize: 14, height: 1.5)),
            // 表情回应
            if (c.reactions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4, children: c.reactions.map((r) =>
                GestureDetector(
                  onTap: () => _toggleReaction(r.sticker),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                    child: Text('${_getEmoji(r.sticker)} ${r.count}',
                      style: const TextStyle(fontSize: 12)),
                  ),
                )).toList()),
            ],
            // 底部操作栏
            const SizedBox(height: 8),
            Row(children: [
              // 表情
              if (c.isSakura)
                _actionButton(Icons.emoji_emotions_outlined, '', _showStickerPicker, cs),
              const SizedBox(width: 12),
              // 回复
              if (c.isSakura)
                _actionButton(Icons.reply_outlined, '回复 ${c.replyCount}', _toggleReplyInput, cs),
              // 删除（仅自己的樱花评论）
              if (c.isSakura && _isMine(c.uid)) ...[
                const SizedBox(width: 12),
                _actionButton(Icons.delete_outline, '删除', _deleteComment, cs),
              ],
              // 举报（别人的樱花评论）
              if (c.isSakura && !_isMine(c.uid)) ...[
                const SizedBox(width: 12),
                _actionButton(Icons.flag_outlined, '举报', _reportComment, cs),
              ],
              // 展开回复
              if (c.replies.isNotEmpty) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => setState(() => _showReplies = !_showReplies),
                  child: Text(_showReplies ? '收起' : '展开${c.replies.length}条回复',
                    style: TextStyle(fontSize: 12, color: cs.primary)),
                ),
              ],
              const Spacer(),
              // 点赞 —— 右下角（横排，心形，点红/取消，会话内缓存）
              _likeButton(cs),
              const SizedBox(width: 8),
              // 点踩
              _actionButton(Icons.thumb_down_outlined, '${c.dislikes}', () => _vote(-1), cs),
            ]),
            // 回复输入框
            if (_showReplyInput) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(
                  controller: _replyController,
                  decoration: InputDecoration(
                    hintText: '回复 ${c.sender}...',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                )),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _submitReply,
                  icon: Icon(Icons.send, color: cs.primary)),
              ]),
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
                      Text(r.sender, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: r.isSakura ? cs.primary.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(3)),
                        child: Text(r.isSakura ? '樱花' : 'Bangumi',
                          style: TextStyle(fontSize: 9, color: r.isSakura ? cs.primary : Colors.orange)),
                      ),
                      const SizedBox(width: 6),
                      Text(r.timeAgo, style: TextStyle(fontSize: 10, color: cs.outline)),
                    ]),
                    const SizedBox(height: 4),
                    BgmRichText(r.content, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap, ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: cs.outline),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 12, color: cs.outline)),
        ],
      ]),
    );
  }

  /// 会话内点过赞的评论 id 缓存（刷新后仍保持，重进页面后重置）
  static final Set<int> _likedIds = <int>{};
  bool _showReplyInput = false;
  void _toggleReplyInput() {
    if (!AuthService.isLoggedIn) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录'))); return; }
    setState(() => _showReplyInput = !_showReplyInput);
  }

  Future<void> _vote(int value) async {
    if (!AuthService.isLoggedIn) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录'))); return; }
    await EpisodeCommentService.vote(commentId: widget.comment.id, value: value);
    widget.onRefresh?.call();
  }

  /// 快手风格：右下角点赞按钮（横排，心形 + 数字，点红/取消）
  Widget _likeButton(ColorScheme cs) {
    final liked = _likedIds.contains(widget.comment.id);
    return GestureDetector(
      onTap: _toggleLike,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(liked ? Icons.favorite : Icons.favorite_border,
              size: 16, color: liked ? Colors.redAccent : cs.outline),
          const SizedBox(width: 3),
          Text('${widget.comment.likes}',
              style: TextStyle(fontSize: 12, color: liked ? Colors.redAccent : cs.outline)),
        ]),
      ),
    );
  }

  Future<void> _toggleLike() async {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    final liked = _likedIds.contains(widget.comment.id);
    final res = await EpisodeCommentService.vote(
        commentId: widget.comment.id, value: liked ? 0 : 1);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        liked ? _likedIds.remove(widget.comment.id) : _likedIds.add(widget.comment.id);
      });
      widget.onRefresh?.call();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res['error'] ?? '操作失败')));
    }
  }

  Future<void> _toggleReaction(String sticker) async {
    if (!AuthService.isLoggedIn) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录'))); return; }
    await EpisodeCommentService.react(commentId: widget.comment.id, sticker: sticker);
    widget.onRefresh?.call();
  }

  Future<void> _submitReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    await EpisodeCommentService.replyComment(commentId: widget.comment.id, content: text);
    _replyController.clear();
    setState(() => _showReplyInput = false);
    widget.onRefresh?.call();
  }

  bool _isMine(String uid) {
    final myUid = SocialService.restoreLocalProfile()?.uid ?? '';
    return myUid.isNotEmpty && uid.isNotEmpty && uid == myUid;
  }

  Future<void> _deleteComment() async {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('确定删除这条评论吗？其下回复也会一并删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await EpisodeCommentService.removeComment(widget.comment.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['success'] == true ? '已删除' : (res['error'] ?? '删除失败'))));
    widget.onRefresh?.call();
  }

  Future<void> _reportComment() async {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('举报评论'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '请填写举报理由（必填）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('提交')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    final res = await EpisodeCommentService.reportComment(commentId: widget.comment.id, reason: reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['success'] == true ? '举报已提交，感谢反馈' : (res['error'] ?? '举报失败'))));
  }

  void _showStickerPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => FutureBuilder<List<Map<String, String>>>(
        future: EpisodeCommentService.getStickers(),
        builder: (ctx, snap) {
          final stickers = snap.data ?? [];
          return Container(
            padding: const EdgeInsets.all(16),
            height: 200,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: stickers.length,
              itemBuilder: (ctx, i) {
                final s = stickers[i];
                return GestureDetector(
                  onTap: () { Navigator.pop(ctx); _toggleReaction(s['id']!); },
                  child: Center(child: Text(_getEmoji(s['id']!), style: const TextStyle(fontSize: 24))),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _getEmoji(String sticker) {
    const map = {
      'bgm1':'👍','bgm2':'❤️','bgm3':'😂','bgm4':'😮','bgm5':'😢','bgm6':'😡',
      'bgm7':'🎉','bgm8':'🔥','bgm9':'💀','bgm10':'👀','bgm11':'🤡','bgm12':'💔',
      'bgm13':'✅','bgm14':'❌','bgm15':'💪','bgm16':'🙏',
    };
    return map[sticker] ?? '👍';
  }
}

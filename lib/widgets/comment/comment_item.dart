import 'package:flutter/material.dart';
import 'package:kazumi/models/episode_comment.dart';
import 'package:kazumi/services/comment/episode_comment_service.dart';
import 'package:kazumi/services/auth_service.dart';

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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：头像 + 昵称 + 来源标签 + 时间
            Row(children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: c.isSakura ? cs.primaryContainer : Colors.orange.shade100,
                child: Text(c.sender.isNotEmpty ? c.sender[0].toUpperCase() : '?',
                  style: TextStyle(fontSize: 14, color: c.isSakura ? cs.primary : Colors.orange)),
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
            Text(c.content, style: const TextStyle(fontSize: 14, height: 1.5)),
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
              // 点赞
              _actionButton(Icons.thumb_up_outlined, '${c.likes}', () => _vote(1), cs),
              const SizedBox(width: 12),
              // 点踩
              _actionButton(Icons.thumb_down_outlined, '${c.dislikes}', () => _vote(-1), cs),
              const SizedBox(width: 12),
              // 表情
              if (c.isSakura)
                _actionButton(Icons.emoji_emotions_outlined, '', _showStickerPicker, cs),
              const SizedBox(width: 12),
              // 回复
              if (c.isSakura)
                _actionButton(Icons.reply_outlined, '回复 ${c.replyCount}', _toggleReplyInput, cs),
              const Spacer(),
              // 展开回复
              if (c.replies.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _showReplies = !_showReplies),
                  child: Text(_showReplies ? '收起' : '展开${c.replies.length}条回复',
                    style: TextStyle(fontSize: 12, color: cs.primary)),
                ),
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
                    Text(r.content, style: const TextStyle(fontSize: 13)),
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

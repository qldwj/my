import 'package:flutter/material.dart';
import 'package:kazumi/services/comment/episode_comment_service.dart';
import 'package:kazumi/services/auth_service.dart';

class CommentEditor extends StatefulWidget {
  final int subjectId;
  final int episode;
  final Function() onSubmitted;
  const CommentEditor({super.key, required this.subjectId, required this.episode, required this.onSubmitted});
  @override
  State<CommentEditor> createState() => _CommentEditorState();
}

class _CommentEditorState extends State<CommentEditor> {
  final _controller = TextEditingController();
  bool _preview = false;
  bool _sending = false;
  int _selectedEpisode = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline.withOpacity(0.2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 集数选择 + 预览切换
          Row(children: [
            // 集数选择
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(6)),
              child: DropdownButton<int>(
                value: _selectedEpisode,
                underline: const SizedBox(),
                isDense: true,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('条目', style: TextStyle(fontSize: 13))),
                  for (int i = 1; i <= 24; i++)
                    DropdownMenuItem(value: i, child: Text('第$i集', style: const TextStyle(fontSize: 13))),
                ],
                onChanged: (v) => setState(() => _selectedEpisode = v ?? 0),
              ),
            ),
            const Spacer(),
            // 预览切换
            TextButton.icon(
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(_preview ? Icons.edit : Icons.preview, size: 16),
              label: Text(_preview ? '编辑' : '预览', style: const TextStyle(fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 8),
          // 输入框 / 预览
          if (_preview)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outline.withOpacity(0.2)),
              ),
              child: Text(_controller.text.isEmpty ? '暂无内容' : _controller.text,
                style: TextStyle(color: _controller.text.isEmpty ? cs.outline : cs.onSurface)),
            )
          else
            TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 2,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: '写评论...',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12)),
            ),
          const SizedBox(height: 8),
          // 发送按钮
          Row(children: [
            const Spacer(),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 16),
              label: const Text('发送', style: TextStyle(fontSize: 13)),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!AuthService.isLoggedIn) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录'))); return; }
    setState(() => _sending = true);
    final res = await EpisodeCommentService.addComment(
      subjectId: widget.subjectId,
      episode: _selectedEpisode,
      content: text,
    );
    setState(() => _sending = false);
    if (res['success'] == true) {
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('评论已发送')));
      widget.onSubmitted();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? '发送失败')));
    }
  }
}

import 'package:flutter/material.dart';
import 'package:kazumi/services/comment/episode_comment_service.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/utils/bgm_sticker.dart';

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
  late int _selectedEpisode;
  bool _showToolbar = true;

  @override
  void initState() {
    super.initState();
    _selectedEpisode = widget.episode; // 🆕 自动匹配当前集数
  }

  @override
  void didUpdateWidget(CommentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode != widget.episode) {
      _selectedEpisode = widget.episode; // 🆕 切换集数时同步
    }
  }

  // 表情改为本地资源（见 lib/utils/bgm_sticker.dart），不再引用失效的远程链接。
  // 可用表情 id 见 BgmSticker.allIds（bgm1..bgm23）。

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
              child: _renderPreview(),
            )
          else
            TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 2,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: '写评论... 支持 BBCode',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12)),
            ),
          const SizedBox(height: 8),
          // BBCode 工具栏
          if (!_preview) ...[
            _buildToolbar(cs),
            const SizedBox(height: 8),
          ],
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

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _toolBtn('B', () => _insert('[b]', '[/b]'), FontWeight.bold, cs),
          _toolBtn('I', () => _insert('[i]', '[/i]'), FontWeight.normal, cs, FontStyle.italic),
          _toolBtn('U', () => _insert('[u]', '[/u]'), FontWeight.normal, cs),
          _toolBtn('S', () => _insert('[s]', '[/s]'), FontWeight.normal, cs),
          _toolBtn('颜色', () => _insert('[color=red]', '[/color]'), null, cs),
          _toolBtn('大小', () => _insert('[size=14]', '[/size]'), null, cs),
          _toolBtn('链接', () => _insert('[url]', '[/url]'), null, cs),
          _toolBtn('图片', () => _insert('[img]', '[/img]'), null, cs),
          _toolBtn('马赛克', () => _insert('[mask]', '[/mask]'), null, cs),
          // 表情按钮
          GestureDetector(
            onTap: _showStickerPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4)),
              child: const Text('😀', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(String label, VoidCallback onTap, FontWeight? weight, ColorScheme cs, [FontStyle? style]) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: weight, fontStyle: style)),
      ),
    );
  }

  void _insert(String before, String after) {
    final text = _controller.text;
    final sel = _controller.selection;
    final selected = text.substring(sel.start, sel.end);
    final newText = text.substring(0, sel.start) + before + selected + after + text.substring(sel.end);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: sel.start + before.length + selected.length);
  }

  void _showStickerPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: 250,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择表情', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
                itemCount: BgmSticker.allIds.length,
                itemBuilder: (ctx, i) {
                  final id = BgmSticker.allIds[i];
                  final asset = BgmSticker.assetFor(id);
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _insert('($id)', '');
                    },
                    child: Center(
                      child: asset != null
                          ? Image.asset(asset, height: 28, width: 28,
                              errorBuilder: (_, __, ___) => Text(id))
                          : Text(id),
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

  Widget _renderPreview() {
    final text = _controller.text;
    if (text.isEmpty) {
      return Text('暂无内容', style: TextStyle(color: Theme.of(context).colorScheme.outline));
    }

    final spans = <InlineSpan>[];
    final regex = RegExp(r'\[(b|i|u|s|mask|color=([^\]]+)|size=(\d+)|url(=([^\]]+))?|img)\](.+?)\[/\1\]', dotAll: true);
    final emojiRegex = RegExp(r'\(bgm(\d+)\)');

    int lastEnd = 0;
    for (final em in emojiRegex.allMatches(text)) {
      if (em.start > lastEnd) {
        _appendBBCode(spans, text.substring(lastEnd, em.start), regex);
      }
      final id = 'bgm${em.group(1)}';
      final asset = BgmSticker.assetFor(id);
      if (asset != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Image.asset(asset, height: 18, width: 18,
                errorBuilder: (_, __, ___) => Text('($id)')),
          ),
        ));
      } else {
        spans.add(TextSpan(text: '($id)'));
      }
      lastEnd = em.end;
    }
    if (lastEnd < text.length) {
      _appendBBCode(spans, text.substring(lastEnd), regex);
    }
    if (spans.isEmpty) return Text(text);

    return RichText(text: TextSpan(children: spans, style: const TextStyle(fontSize: 14, height: 1.5)));
  }

  void _appendBBCode(List<InlineSpan> spans, String segment, RegExp regex) {
    if (segment.isEmpty) return;
    int lastEnd = 0;
    for (final match in regex.allMatches(segment)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: segment.substring(lastEnd, match.start)));
      }
      final tag = match.group(1)!;
      final content = match.group(match.groupCount) ?? '';
      switch (tag) {
        case 'b': spans.add(TextSpan(text: content, style: const TextStyle(fontWeight: FontWeight.bold))); break;
        case 'i': spans.add(TextSpan(text: content, style: TextStyle(fontStyle: FontStyle.italic))); break;
        case 'u': spans.add(TextSpan(text: content, style: TextStyle(decoration: TextDecoration.underline))); break;
        case 's': spans.add(TextSpan(text: content, style: TextStyle(decoration: TextDecoration.lineThrough))); break;
        case 'mask': spans.add(TextSpan(text: content, style: TextStyle(color: Colors.transparent, backgroundColor: Colors.grey))); break;
        case 'color': spans.add(TextSpan(text: content, style: TextStyle(color: _parseColor(match.group(2) ?? 'white')))); break;
        case 'size': spans.add(TextSpan(text: content, style: TextStyle(fontSize: double.tryParse(match.group(3) ?? '14')))); break;
        default: spans.add(TextSpan(text: content));
      }
      lastEnd = match.end;
    }
    if (lastEnd < segment.length) {
      spans.add(TextSpan(text: segment.substring(lastEnd)));
    }
  }

  Color _parseColor(String name) {
    const colors = {'red': Colors.red, 'blue': Colors.blue, 'green': Colors.green, 'orange': Colors.orange, 'yellow': Colors.yellow, 'purple': Colors.purple, 'pink': Colors.pink};
    return colors[name.toLowerCase()] ?? Colors.white;
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

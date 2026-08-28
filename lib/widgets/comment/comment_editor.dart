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
  bool _showToolbar = true;

  // 表情列表
  static const Map<String, String> _stickers = {
    'bgm1': 'https://lain.bgm.tv/r/express/l/bgm/bgm1.gif',
    'bgm2': 'https://lain.bgm.tv/r/express/l/bgm/bgm2.gif',
    'bgm3': 'https://lain.bgm.tv/r/express/l/bgm/bgm3.gif',
    'bgm4': 'https://lain.bgm.tv/r/express/l/bgm/bgm4.gif',
    'bgm5': 'https://lain.bgm.tv/r/express/l/bgm/bgm5.gif',
    'bgm6': 'https://lain.bgm.tv/r/express/l/bgm/bgm6.gif',
    'bgm7': 'https://lain.bgm.tv/r/express/l/bgm/bgm7.gif',
    'bgm8': 'https://lain.bgm.tv/r/express/l/bgm/bgm8.gif',
    'bgm9': 'https://lain.bgm.tv/r/express/l/bgm/bgm9.gif',
    'bgm10': 'https://lain.bgm.tv/r/express/l/bgm/bgm10.gif',
    'bgm11': 'https://lain.bgm.tv/r/express/l/bgm/bgm11.gif',
    'bgm12': 'https://lain.bgm.tv/r/express/l/bgm/bgm12.gif',
    'bgm13': 'https://lain.bgm.tv/r/express/l/bgm/bgm13.gif',
    'bgm14': 'https://lain.bgm.tv/r/express/l/bgm/bgm14.gif',
    'bgm15': 'https://lain.bgm.tv/r/express/l/bgm/bgm15.gif',
    'bgm16': 'https://lain.bgm.tv/r/express/l/bgm/bgm16.gif',
    'bgm17': 'https://lain.bgm.tv/r/express/l/bgm/bgm17.gif',
    'bgm18': 'https://lain.bgm.tv/r/express/l/bgm/bgm18.gif',
    'bgm19': 'https://lain.bgm.tv/r/express/l/bgm/bgm19.gif',
    'bgm20': 'https://lain.bgm.tv/r/express/l/bgm/bgm20.gif',
    'bgm21': 'https://lain.bgm.tv/r/express/l/bgm/bgm21.gif',
    'bgm22': 'https://lain.bgm.tv/r/express/l/bgm/bgm22.gif',
    'bgm23': 'https://lain.bgm.tv/r/express/l/bgm/bgm23.gif',
    'bgm24': 'https://lain.bgm.tv/r/express/l/bgm/bgm24.gif',
    'bgm25': 'https://lain.bgm.tv/r/express/l/bgm/bgm25.gif',
    'bgm26': 'https://lain.bgm.tv/r/express/l/bgm/bgm26.gif',
    'bgm27': 'https://lain.bgm.tv/r/express/l/bgm/bgm27.gif',
    'bgm28': 'https://lain.bgm.tv/r/express/l/bgm/bgm28.gif',
  };

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
                itemCount: _stickers.length,
                itemBuilder: (ctx, i) {
                  final entry = _stickers.entries.elementAt(i);
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _insert('(${entry.key})', '');
                    },
                    child: Center(child: Text(entry.value, style: const TextStyle(fontSize: 24))),
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
    if (text.isEmpty) return Text('暂无内容', style: TextStyle(color: Theme.of(context).colorScheme.outline));
    
    // 简单 BBCode 渲染
    final spans = <TextSpan>[];
    final regex = RegExp(r'\[(b|i|u|s|mask|color=([^\]]+)|size=(\d+)|url(=([^\]]+))?|img)\](.+?)\[/\1\]', dotAll: true);
    final emojiRegex = RegExp(r'\(bgm(\d+)\)');
    
    // 先解析表情
    final parts = text.split(emojiRegex);
    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 1) {
        final emoji = _stickers['bgm$parts[i]'] ?? '👍';
        spans.add(TextSpan(text: emoji, style: const TextStyle(fontSize: 18)));
      } else if (parts[i].isNotEmpty) {
        // 解析 BBCode
        int lastEnd = 0;
        for (final match in regex.allMatches(parts[i])) {
          if (match.start > lastEnd) {
            spans.add(TextSpan(text: parts[i].substring(lastEnd, match.start)));
          }
          final tag = match.group(1)!;
          final content = match.group(match.groupCount) ?? '';
          switch (tag) {
            case 'b': spans.add(TextSpan(text: content, style: const TextStyle(fontWeight: FontWeight.bold))); break;
            case 'i': spans.add(TextSpan(text: content, style: const TextStyle(fontStyle: FontStyle.italic))); break;
            case 'u': spans.add(TextSpan(text: content, style: const TextStyle(decoration: TextDecoration.underline))); break;
            case 's': spans.add(TextSpan(text: content, style: const TextStyle(decoration: TextDecoration.lineThrough))); break;
            case 'mask': spans.add(TextSpan(text: content, style: const TextStyle(color: Colors.transparent, backgroundColor: Colors.grey))); break;
            case 'color': spans.add(TextSpan(text: content, style: TextStyle(color: _parseColor(match.group(2) ?? 'white')))); break;
            case 'size': spans.add(TextSpan(text: content, style: TextStyle(fontSize: double.tryParse(match.group(3) ?? '14')))); break;
            default: spans.add(TextSpan(text: content));
          }
          lastEnd = match.end;
        }
        if (lastEnd < parts[i].length) {
          spans.add(TextSpan(text: parts[i].substring(lastEnd)));
        }
      }
    }
    
    return RichText(text: TextSpan(children: spans.isEmpty ? [TextSpan(text: text)] : spans));
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

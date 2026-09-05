import 'package:flutter/material.dart';
import 'package:kazumi/utils/bgm_sticker.dart';

/// 将评论文本中的 `(bgmN)` 渲染为本地表情图，其余按普通文本显示。
///
/// 与 Ani 的行为一致：编辑框里输入 `(bgm1)` 发送后，评论区直接显示为表情图。
class BgmRichText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final double emojiSize;

  const BgmRichText(
    this.text, {
    this.style,
    this.emojiSize = 18,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final regex = RegExp(r'\(bgm(\d+)\)');
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, m.start), style: style));
      }
      final id = 'bgm${m.group(1)}';
      final asset = BgmSticker.assetFor(id);
      if (asset != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Image.asset(
                asset,
                height: emojiSize,
                width: emojiSize,
                errorBuilder: (_, __, ___) => Text('($id)'),
              ),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: '($id)', style: style));
      }
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: style));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: style));
    }
    return RichText(text: TextSpan(children: spans, style: style));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:kazumi/utils/bgm_sticker.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';

/// 将评论文本中的以下内容渲染为对应效果：
/// 1. `(bgmN)` → 本地表情图
/// 2. 图片直链（.jpg/.png/.webp/.gif 等）→ 直接内联显示图片/GIF（走 App 图片加速）
/// 3. 普通网址（http/https）→ 可点击链接（点击复制/提示）
/// 4. BBCode [url]/[img] → 同上
///
/// 樱花动漫 与 Bangumi 的吐槽都走这里，格式统一。
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

  /// 图片/GIF 直链
  static final _imageRegex = RegExp(
    r'https?://[^\s\[\]()<>"\u4e00-\u9fa5]+\.(?:jpg|jpeg|png|gif|webp|bmp|avif|svg)(?:\?[^\s\[\]()<>"]*)?',
    caseSensitive: false,
  );
  /// 普通网址
  static final _urlRegex = RegExp(
    r'https?://[^\s\[\]()<>"\u4e00-\u9fa5]+',
    caseSensitive: false,
  );
  /// 表情 (bgmN)
  static final _emojiRegex = RegExp(r'\(bgm(\d+)\)');

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ??
        TextStyle(
          fontSize: 14,
          height: 1.5,
          color: Theme.of(context).colorScheme.onSurface,
        );

    final widgets = <Widget>[];
    var cursor = 0;

    // 收集所有特殊片段（表情/图片/链接），按位置排序
    final marks = <_Mark>[];
    for (final m in _emojiRegex.allMatches(text)) {
      marks.add(_Mark(m.start, m.end, _MarkKind.emoji, m.group(1)!));
    }
    for (final m in _imageRegex.allMatches(text)) {
      marks.add(_Mark(m.start, m.end, _MarkKind.image, m.group(0)!));
    }
    for (final m in _urlRegex.allMatches(text)) {
      // 已被图片匹配覆盖的跳过
      if (marks.any((k) =>
          k.kind == _MarkKind.image && k.start <= m.start && k.end >= m.end)) {
        continue;
      }
      marks.add(_Mark(m.start, m.end, _MarkKind.url, m.group(0)!));
    }
    marks.sort((a, b) => a.start.compareTo(b.start));

    // 去重/跳过重叠
    final accepted = <_Mark>[];
    var lastAcceptedEnd = -1;
    for (final k in marks) {
      if (k.start < lastAcceptedEnd) continue;
      accepted.add(k);
      lastAcceptedEnd = k.end;
    }

    for (final k in accepted) {
      if (k.start > cursor) {
        widgets.add(_segment(text.substring(cursor, k.start), baseStyle));
      }
      switch (k.kind) {
        case _MarkKind.emoji:
          widgets.add(_emojiWidget('bgm${k.value}', baseStyle));
          break;
        case _MarkKind.image:
          widgets.add(_imageWidget(k.value));
          break;
        case _MarkKind.url:
          widgets.add(_linkWidget(context, k.value, baseStyle));
          break;
      }
      cursor = k.end;
    }
    if (cursor < text.length) {
      widgets.add(_segment(text.substring(cursor), baseStyle));
    }
    if (widgets.isEmpty) {
      widgets.add(_segment(text, baseStyle));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  /// 文本段：内部再处理表情（把 (bgmN) 渲染为图片）
  Widget _segment(String t, TextStyle s) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _emojiRegex.allMatches(t)) {
      if (m.start > last) {
        spans.add(TextSpan(text: t.substring(last, m.start), style: s));
      }
      spans.add(_emojiSpan('bgm${m.group(1)}', s));
      last = m.end;
    }
    if (last < t.length) {
      spans.add(TextSpan(text: t.substring(last), style: s));
    }
    return RichText(
      text: TextSpan(children: spans, style: s),
    );
  }

  Widget _emojiWidget(String id, TextStyle s) {
    final asset = BgmSticker.assetFor(id);
    if (asset == null) return Text('($id)', style: s);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Image.asset(
        asset,
        height: emojiSize,
        width: emojiSize,
        errorBuilder: (_, __, ___) => Text('($id)', style: s),
      ),
    );
  }

  InlineSpan _emojiSpan(String id, TextStyle s) {
    final asset = BgmSticker.assetFor(id);
    if (asset == null) return TextSpan(text: '($id)', style: s);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Image.asset(
          asset,
          height: emojiSize,
          width: emojiSize,
          errorBuilder: (_, __, ___) => Text('($id)', style: s),
        ),
      ),
    );
  }

  /// 图片/GIF：走 App 统一图片管线（自动享受 ECH / 镜像加速）
  Widget _imageWidget(String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: NetworkImgLayer(
          src: url,
          width: 220,
          height: 220,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  /// 普通链接：可点击（点击后由 App 决定行为，这里先提示可复制）
  Widget _linkWidget(BuildContext context, String url, TextStyle s) {
    final linkColor = Theme.of(context).colorScheme.primary;
    return Text.rich(
      TextSpan(
        text: url,
        style: s.copyWith(color: linkColor, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            // 用对话框展示，方便复制/打开
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('链接'),
                content: SelectableText(url,
                    style: const TextStyle(fontSize: 13)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            );
          },
      ),
    );
  }
}

enum _MarkKind { emoji, image, url }

class _Mark {
  const _Mark(this.start, this.end, this.kind, this.value);
  final int start;
  final int end;
  final _MarkKind kind;
  final String value;
}

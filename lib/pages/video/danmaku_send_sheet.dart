import 'package:flutter/material.dart';

/// 返回 (弹幕文本, 位置类型) — 1=滚动 4=底部(置底) 5=顶部(置顶)
Future<({String text, int type})?> showMobileDanmakuInputSheet(
    BuildContext context) {
  return showModalBottomSheet<({String text, int type})>(
    context: context,
    shape: const BeveledRectangleBorder(),
    isScrollControlled: true,
    builder: (context) => const _MobileDanmakuInputSheet(),
  );
}

class _MobileDanmakuInputSheet extends StatefulWidget {
  const _MobileDanmakuInputSheet();

  @override
  State<_MobileDanmakuInputSheet> createState() =>
      _MobileDanmakuInputSheetState();
}

class _MobileDanmakuInputSheetState extends State<_MobileDanmakuInputSheet> {
  String _danmakuText = '';
  int _selectedType = 1; // 1=滚动 5=顶部(置顶) 4=底部(置底)

  void _submit([String? value]) {
    Navigator.of(context)
        .pop((text: value ?? _danmakuText, type: _selectedType));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 34),
              child: TextField(
                style: const TextStyle(fontSize: 15),
                autofocus: true,
                textInputAction: TextInputAction.send,
                textAlignVertical: TextAlignVertical.center,
                onChanged: (value) => _danmakuText = value,
                onSubmitted: _submit,
                decoration: const InputDecoration(
                  filled: true,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  hintText: '发个友善的弹幕见证当下',
                  hintStyle: TextStyle(fontSize: 14),
                  alignLabelWithHint: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                ),
              ),
            ),
          ),
          // ⭐ 弹幕位置：滚动 / 置顶 / 置底
          _TypeButton(
            icon: Icons.swap_horiz_rounded,
            tooltip: '滚动',
            selected: _selectedType == 1,
            onTap: () => setState(() => _selectedType = 1),
          ),
          _TypeButton(
            icon: Icons.vertical_align_top_rounded,
            tooltip: '置顶',
            selected: _selectedType == 5,
            onTap: () => setState(() => _selectedType = 5),
          ),
          _TypeButton(
            icon: Icons.vertical_align_bottom_rounded,
            tooltip: '置底',
            selected: _selectedType == 4,
            onTap: () => setState(() => _selectedType = 4),
          ),
          IconButton(
            tooltip: '发送',
            onPressed: _submit,
            icon: Icon(
              Icons.send_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 弹幕位置小按钮
class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 20,
        color: selected
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

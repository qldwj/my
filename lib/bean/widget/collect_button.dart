import 'package:flutter/material.dart';
import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/pages/collect/collect_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/widget/kazumi_menu.dart';
import 'package:yhdm/modules/collect/collect_type.dart';

class CollectButton extends StatefulWidget {
  const CollectButton({
    super.key,
    required this.bangumiItem,
    this.color = Colors.white,
    this.onOpen,
    this.onClose,
  }) : _isExtended = false;

  const CollectButton.extend({
    super.key,
    required this.bangumiItem,
    this.color = Colors.white,
    this.onOpen,
    this.onClose,
  }) : _isExtended = true;

  final BangumiItem bangumiItem;
  final Color color;
  final bool _isExtended;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  @override
  State<CollectButton> createState() => _CollectButtonState();
}

class _CollectButtonState extends State<CollectButton> {
  final _collectController = inject<CollectController>();

  String _labelFor(CollectType type) =>
      type == CollectType.none ? '未追' : type.label;

  IconData _iconFor(CollectType type) => switch (type) {
    CollectType.none => Icons.favorite_border,
    CollectType.watching => Icons.favorite,
    CollectType.planToWatch => Icons.star_rounded,
    CollectType.onHold => Icons.pending_actions,
    CollectType.watched => Icons.done,
    CollectType.abandoned => Icons.heart_broken,
  };

  Future<void> _selectType(CollectType type) async {
    if (!mounted ||
        type.value == _collectController.getCollectType(widget.bangumiItem)) {
      return;
    }
    await _collectController.addCollect(widget.bangumiItem, type: type.value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final collectType = CollectType.fromValue(
      _collectController.getCollectType(widget.bangumiItem),
    );
    return KazumiMenuButton(
      onClose: widget.onClose,
      onOpen: widget.onOpen,
      animated: true, // 🆕 菜单弹出动画
      crossAxisUnconstrained: false,
      builder: (context, toggle) {
        // 🆕 状态切换时图标平滑过渡（缩放+淡入淡出）
        final animatedIcon = AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(
            _iconFor(collectType),
            key: ValueKey(collectType),
            color: widget.color,
          ),
        );
        return widget._isExtended
            ? FilledButton.icon(
                onPressed: toggle,
                icon: animatedIcon,
                label: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _labelFor(collectType),
                    key: ValueKey(collectType),
                  ),
                ),
              )
            : IconButton(
                onPressed: toggle,
                tooltip: _labelFor(collectType),
                icon: animatedIcon,
              );
      },
      menuChildren: [
        for (final type in CollectType.values)
          KazumiMenuItem(
            label: _labelFor(type),
            selected: type == collectType,
            onPressed: () => _selectType(type),
          ),
      ],
    );
  }
}

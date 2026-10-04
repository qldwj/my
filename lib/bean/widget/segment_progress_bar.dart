import 'package:flutter/material.dart';

/// 整段加载进度条：一大段高亮从右往左扫过、循环往复。
/// 模仿主页加载动画风格，用于选集上方等加载场景。
class SegmentProgressBar extends StatefulWidget {
  const SegmentProgressBar({
    super.key,
    this.height = 5,
    this.duration = const Duration(milliseconds: 1100),
    this.highlightRatio = 0.42,
    this.borderRadius = 3,
  });

  final double height;
  final Duration duration;

  /// 高亮段占轨道宽度的比例（一整大段）。
  final double highlightRatio;

  final double borderRadius;

  @override
  State<SegmentProgressBar> createState() => _SegmentProgressBarState();
}

class _SegmentProgressBarState extends State<SegmentProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration)
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth;
              final highlightWidth =
                  (available * widget.highlightRatio).clamp(24.0, available);
              // 高亮段从右往左扫过：t=0 在最右，t=1 在最左
              final left = (1 - t) * (available - highlightWidth);
              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(widget.borderRadius),
                    ),
                  ),
                  Positioned(
                    left: left,
                    top: 0,
                    bottom: 0,
                    width: highlightWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius:
                            BorderRadius.circular(widget.borderRadius),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

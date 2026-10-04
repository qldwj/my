import 'package:flutter/material.dart';

/// 分段加载进度条：一段一段往右推进、永不满格。
/// 模仿主页加载动画的轻量加载指示，用于选集上方等加载场景。
class SegmentProgressBar extends StatefulWidget {
  const SegmentProgressBar({
    super.key,
    this.segmentCount = 8,
    this.activeSegments = 2,
    this.height = 5,
    this.duration = const Duration(milliseconds: 900),
    this.borderRadius = 3,
  });

  final int segmentCount;
  final int activeSegments;
  final double height;
  final Duration duration;
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
    final gap = widget.height * 0.6;
    final segmentCount = widget.segmentCount;
    final active =
        widget.activeSegments.clamp(1, segmentCount);
    // 高亮「起始段」的可滑动位置数量
    final totalSteps = segmentCount - active + 1;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final startIndex = (t * totalSteps).floor() % totalSteps;
        return SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth;
              final segWidth =
                  (available - gap * (segmentCount - 1)) / segmentCount;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(segmentCount, (i) {
                  final isActive = i >= startIndex && i < startIndex + active;
                  return Container(
                    width: segWidth,
                    margin: EdgeInsets.symmetric(horizontal: gap / 2),
                    decoration: BoxDecoration(
                      color: isActive
                          ? color
                          : color.withValues(alpha: 0.15),
                      borderRadius:
                          BorderRadius.circular(widget.borderRadius),
                    ),
                  );
                }),
              );
            },
          ),
        );
      },
    );
  }
}

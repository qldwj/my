import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 渐变圆环加载动画：一段品牌色渐变弧线绕圆环旋转，弧长轻微呼吸。
/// 比旧版 MaterialShapes 形变旋转更简洁精致，适配深浅色主题。
class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.semanticsLabel = '加载中',
  });

  final double size;
  final Color? color;
  final String semanticsLabel;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _RingPainter(
              animation: _controller,
              color: widget.color ?? Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.animation, required this.color})
      : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final center = size.center(Offset.zero);
    final radius = size.width * 0.38;
    final stroke = size.width * 0.12;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // 弧长呼吸：0.3π ~ 1.1π
    final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final sweep = math.pi * (0.3 + 0.4 * breathe);
    final start = -math.pi / 2 + t * 2 * math.pi;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 弧线渐变：尾部淡、头部浓，随旋转呈现扫光效果
    paint.shader = SweepGradient(
      startAngle: start - sweep * 0.35,
      endAngle: start + sweep,
      colors: [
        color.withValues(alpha: 0.06),
        color.withValues(alpha: 0.35),
        color,
      ],
    ).createShader(rect);

    canvas.drawArc(rect, start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.color != color;
}

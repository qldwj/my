import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 自适应加载指示器
class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({super.key, this.size = 48});

  final double size;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _LoadingPainter(
            progress: _controller.value,
            color: colors.primary,
          ),
        );
      },
    );
  }
}

class _LoadingPainter extends CustomPainter {
  _LoadingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // 旋转的圆弧
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final startAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      math.pi * 1.5,
      false,
      paint,
    );

    // 中心点
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(center, 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _LoadingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

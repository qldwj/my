import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/services/tutorial/tutorial_controller.dart';

/// 🆕 新手引导聚光灯层
///
/// 用法：把本组件放在 App 的 builder 里（位于所有页面之上），
/// 由 [TutorialController.instance.start(steps)] 触发。
///
/// 特性：
/// - 半透明遮罩 + 目标控件处挖孔高亮（带连接线指向气泡）
/// - **只有高亮目标可点**，其余区域全部拦截（强制用户按引导操作）
/// - 气泡显示「第 n / 共 m 步」、标题、正文、跳过/上一步/下一步
/// - 某步带 [TutorialStep.route] 时，跳转路由
/// - 某步带 [TutorialStep.advanceEvent] 时，等真实操作事件才推进
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  final _controller = TutorialController.instance;

  @override
  void initState() {
    super.initState();
    _controller.onNavigate = (route) {
      try {
        context.pushNamed(route);
      } catch (_) {}
    };
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
    final step = _controller.current;
    if (step?.route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_controller.active) {
          try {
            context.pushNamed(step!.route!);
          } catch (_) {}
        }
      });
    }
  }

  Rect? _targetRect(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final step = _controller.current;
    return Stack(
      children: [
        widget.child,
        if (step != null) _buildMask(context, step),
      ],
    );
  }

  Widget _buildMask(BuildContext context, TutorialStep step) {
    final size = MediaQuery.sizeOf(context);
    final rawRect = _targetRect(step.targetKey);
    final hole = rawRect?.inflate(step.highlightPadding);

    // 计算气泡位置
    const bubbleWidth = 320.0;
    double? bubbleTop;
    double? bubbleLeft;
    if (hole != null) {
      bubbleLeft = (hole.center.dx - bubbleWidth / 2)
          .clamp(12.0, (size.width - bubbleWidth - 12.0).clamp(12.0, size.width));
      const bubbleHeight = 210.0;
      final below = hole.bottom + 20;
      if (below + bubbleHeight < size.height) {
        bubbleTop = below;
      } else {
        bubbleTop =
            (hole.top - bubbleHeight - 20).clamp(12.0, size.height - bubbleHeight);
      }
    }
    final bubbleRect = (bubbleTop != null && bubbleLeft != null)
        ? Rect.fromLTWH(bubbleLeft, bubbleTop, bubbleWidth, 210)
        : null;

    return Positioned.fill(
      child: Stack(
        children: [
          // 遮罩 + 挖孔 + 连接线：IgnorePointer 保证完全不接收任何手势
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SpotlightPainter(hole: hole, bubble: bubbleRect),
              ),
            ),
          ),
          // 🆕 不做任何交互拦截：用户可自由点击界面；
          // 进度通过气泡里的「下一步」推进（若顺手完成了高亮处操作也会自动推进）
          _buildBubble(context, hole, size, bubbleTop, bubbleLeft),
        ],
      ),
    );
  }

  Widget _buildBubble(BuildContext context, Rect? hole, Size size,
      double? top, double? left) {
    final cs = Theme.of(context).colorScheme;
    final step = _controller.current!;
    const bubbleWidth = 320.0;
    final isLast = _controller.index >= _controller.total - 1;

    final bubble = Container(
      width: bubbleWidth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第 ${_controller.index + 1} 步 / 共 ${_controller.total} 步',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.content,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: () => _controller.finish(),
                child: const Text('一键跳过'),
              ),
              const Spacer(),
              if (_controller.index > 0)
                TextButton(
                  onPressed: () => _controller.prev(),
                  child: const Text('上一步'),
                ),
              const SizedBox(width: 4),
              // 🆕 不拦截手势后，每步都提供「下一步」，用户随时可手动推进；
              // 若他也完成了高亮处的真实操作，事件同样会自动推进
              FilledButton(
                onPressed: () => _controller.next(),
                child: Text(isLast ? '完成' : '下一步'),
              ),
            ],
          ),
        ],
      ),
    );

    if (top == null || left == null) {
      return Center(child: bubble);
    }
    return Positioned(left: left, top: top, child: bubble);
  }
}

/// 遮罩 + 挖孔 + 连接线画笔
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({this.hole, this.bubble});
  final Rect? hole;
  final Rect? bubble;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.62);
    final full = Offset.zero & size;
    if (hole == null) {
      canvas.drawRect(full, paint);
      return;
    }
    final holeRRect =
        RRect.fromRectAndRadius(hole!, const Radius.circular(12));

    // 全屏遮罩挖孔
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      Path()..addRRect(holeRRect),
    );
    canvas.drawPath(path, paint);

    // 高亮描边
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawRRect(holeRRect, border);

    // 气泡 → 挖孔 的连接线
    if (bubble != null) {
      final from = Offset(bubble!.center.dx, bubble!.top);
      final to = Offset(hole!.center.dx, hole!.bottom);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.85);
      // 若气泡在挖孔下方，则从气泡顶部连到挖孔底部；反之从气泡底连到挖孔顶
      if (bubble!.top > hole!.center.dy) {
        canvas.drawLine(from, to, line);
      } else {
        canvas.drawLine(
          Offset(bubble!.center.dx, bubble!.bottom),
          Offset(hole!.center.dx, hole!.top),
          line,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.hole != hole || old.bubble != bubble;
}

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/services/tutorial/tutorial_controller.dart';

/// 🆕 新手引导聚光灯层
///
/// 用法：把本组件放在 App 的 builder 里（位于所有页面之上），
/// 由 [TutorialController.instance.start(steps)] 触发。
///
/// 特性：
/// - 半透明遮罩 + 目标控件处挖孔高亮
/// - 气泡显示「第 n / 共 m 步」、标题、正文、下一步/跳过
/// - 某步带 [TutorialStep.route] 时，点「下一步」会自动跳转
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
    // 切换步骤时，若下一步要求跳转，则执行导航
    final step = _controller.current;
    if (step?.route != null) {
      // 延后一帧，避免在 notify 过程中导航
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

  /// 计算目标控件的屏幕矩形
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
    final rect = rawRect?.inflate(step.highlightPadding);

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // 半透明遮罩 + 挖孔
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SpotlightPainter(hole: rect),
                ),
              ),
            ),
            // 气泡
            _buildBubble(context, rect, size),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context, Rect? hole, Size size) {
    final cs = Theme.of(context).colorScheme;
    final step = _controller.current!;
    const bubbleWidth = 320.0;
    final isLast = _controller.index >= _controller.total - 1;

    // 计算气泡位置：优先放在高亮下方，空间不够则放上方，否则居中
    double? top;
    double? left;
    if (hole != null) {
      left = (hole.center.dx - bubbleWidth / 2)
          .clamp(12.0, size.width - bubbleWidth - 12.0);
      final below = hole.bottom + 16;
      final bubbleHeight = 190.0;
      if (below + bubbleHeight < size.height) {
        top = below;
      } else {
        top = (hole.top - bubbleHeight - 16).clamp(12.0, size.height - 200);
      }
    }

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
          // 第 n / 共 m 步
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
                onPressed: () {
                  _controller.finish();
                },
                child: const Text('跳过'),
              ),
              const Spacer(),
              if (_controller.index > 0)
                TextButton(
                  onPressed: () => _controller.prev(),
                  child: const Text('上一步'),
                ),
              const SizedBox(width: 4),
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

/// 遮罩 + 挖孔画笔
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({this.hole});
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.62);
    final full = Offset.zero & size;
    if (hole == null) {
      canvas.drawRect(full, paint);
      return;
    }
    // 全屏遮罩挖孔
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      Path()
        ..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(12))),
    );
    canvas.drawPath(path, paint);

    // 高亮描边
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole!, const Radius.circular(12)),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) => old.hole != hole;
}

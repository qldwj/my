import 'package:flutter/material.dart';

/// AnimeFlow 风格的迷你主题预览卡。
///
/// 展示深色/浅色/跟随系统三种外观的迷你界面预览，
/// 选中时播放"圆形滑入 → 变对勾"动画。
class ThemePreviewCard extends StatefulWidget {
  final Color bg;
  final Color primary;
  final IconData icon;
  final String title;
  final Color? titleColor;
  final String subtitle;
  final Color? subtitleColor;
  final bool selected;
  final Widget? overlay;

  const ThemePreviewCard({
    super.key,
    required this.bg,
    required this.primary,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.selected = false,
    this.overlay,
    this.titleColor,
    this.subtitleColor,
  });

  @override
  State<ThemePreviewCard> createState() => _ThemePreviewCardState();
}

class _ThemePreviewCardState extends State<ThemePreviewCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _positionAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _positionAnimation = Tween<double>(
      begin: 0.0,
      end: 64.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
      ),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
      ),
    );

    if (widget.selected) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(ThemePreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      if (widget.selected) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 110,
          height: 160,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.selected ? widget.primary : Colors.white24,
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: widget.primary.withValues(alpha: 0.6),
                      blurRadius: 16,
                    )
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon, color: widget.primary, size: 28),
              const SizedBox(height: 16),
              Text(widget.title,
                  style: TextStyle(
                      color: widget.titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(widget.subtitle,
                  style: TextStyle(fontSize: 12, color: widget.subtitleColor)),
              const Spacer(),
              Container(
                height: 22,
                decoration: BoxDecoration(
                  color: widget.primary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    final circleOpacity = 1.0 - _scaleAnimation.value;
                    final checkOpacity = _scaleAnimation.value;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (circleOpacity > 0.01)
                          Positioned(
                            left: _positionAnimation.value,
                            top: 0,
                            child: IgnorePointer(
                              ignoring: circleOpacity < 0.5,
                              child: Opacity(
                                opacity: circleOpacity,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: widget.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (checkOpacity > 0.01)
                          Positioned(
                            left: _positionAnimation.value,
                            top: 0,
                            child: IgnorePointer(
                              ignoring: checkOpacity < 0.5,
                              child: Opacity(
                                opacity: checkOpacity,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: widget.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        if (widget.overlay != null) widget.overlay!,
      ],
    );
  }
}

/// "跟随系统"卡片上的斜切覆盖层。
class DiagonalOverlay extends StatelessWidget {
  const DiagonalOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ClipPath(
        clipper: _DiagonalClipper(),
        child: Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18), color: Colors.white38),
        ),
      ),
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_) => false;
}

import 'package:flutter/material.dart';

/// 通用加载指示器（旋转圈）
///
/// 与官方 Kazumi 的 loading_indicator 用法对齐：
/// `LoadingIndicator(size: 64, color: colors.primary, semanticsLabel: '...')`
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({
    super.key,
    this.size = 32,
    this.color,
    this.strokeWidth = 4,
    this.semanticsLabel = '加载中',
  });

  final double size;
  final Color? color;
  final double strokeWidth;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          color: color ?? Theme.of(context).colorScheme.primary,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

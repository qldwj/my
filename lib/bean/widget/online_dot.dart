import 'package:flutter/material.dart';

/// 在线状态小圆点（好友头像/名字旁）
///
/// [online] true 显示绿色实心点；false 显示灰色小点（可隐藏）。
class OnlineDot extends StatelessWidget {
  const OnlineDot({
    super.key,
    required this.online,
    this.showOffline = true,
    this.size = 12,
  });

  final bool online;
  final bool showOffline;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!online && !showOffline) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: online ? const Color(0xFF22C55E) : Colors.grey.shade400,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}
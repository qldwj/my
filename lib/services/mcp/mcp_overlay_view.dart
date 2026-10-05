import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// MCP 悬浮窗 UI（运行在独立 Flutter 引擎，由 overlayMain 入口渲染）。
///
/// 显示 MCP 启停状态，点击后向主引擎发送 mcp_toggle 事件切换服务，
/// 并接收主引擎广播的 mcp_status 同步状态。用于防止 App 掉后台保活。
class McpOverlayView extends StatefulWidget {
  const McpOverlayView({super.key});

  @override
  State<McpOverlayView> createState() => _McpOverlayViewState();
}

class _McpOverlayViewState extends State<McpOverlayView> {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    // 接收主引擎广播的 MCP 状态
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map && data['action'] == 'mcp_status' && mounted) {
        setState(() => _running = data['running'] == true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: GestureDetector(
          onTap: () => FlutterOverlayWindow.shareData({'action': 'mcp_toggle'}),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: _running
                  ? const Color(0xffEC407A)
                  : const Color(0xff333333),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _running
                      ? Icons.smart_toy_rounded
                      : Icons.smart_toy_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _running ? 'MCP 运行中' : 'MCP 已关闭',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

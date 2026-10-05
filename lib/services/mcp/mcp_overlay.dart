import 'dart:io';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/mcp/mcp_server.dart';

/// MCP 悬浮窗快捷开关管理。
///
/// 负责：申请悬浮窗权限、显示/隐藏悬浮窗、把 MCP 状态同步给悬浮窗 UI，
/// 以及监听悬浮窗点击事件来切换 MCP 服务的启停。
class McpOverlay {
  McpOverlay._();
  static final McpOverlay instance = McpOverlay._();

  bool _listening = false;

  /// 在 App 主引擎初始化时调用：注册悬浮窗点击事件监听（切换 MCP 启停）。
  void init() {
    if (_listening || !Platform.isAndroid) return;
    _listening = true;
    FlutterOverlayWindow.overlayListener.listen(_onOverlayEvent);
  }

  void _onOverlayEvent(Object? data) {
    if (data is! Map || data['action'] != 'mcp_toggle') return;
    final srv = McpServer.instance;
    try {
      if (srv.isRunning) {
        srv.stop();
        KazumiLogger().i('McpOverlay: 悬浮窗点击 -> 已停止 MCP');
      } else {
        srv.start();
        KazumiLogger().i('McpOverlay: 悬浮窗点击 -> 已启动 MCP');
      }
    } catch (e) {
      KazumiLogger().e('McpOverlay: 点击切换失败: $e');
    }
    // 同步新状态给悬浮窗 UI
    broadcast();
  }

  /// 申请悬浮窗权限（Android）。返回是否已授权。
  Future<bool> ensurePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (granted) {
        KazumiLogger().i('McpOverlay: 悬浮窗权限已授权');
        return true;
      }
      KazumiLogger().i('McpOverlay: 未授权，跳转系统设置申请');
      await FlutterOverlayWindow.requestPermission();
      final after = await FlutterOverlayWindow.isPermissionGranted();
      KazumiLogger().i('McpOverlay: 申请后授权状态 = $after');
      return after;
    } catch (e) {
      KazumiLogger().e('McpOverlay: 申请悬浮窗权限异常: $e');
      return false;
    }
  }

  /// 显示悬浮窗。返回是否成功显示。
  Future<bool> show() async {
    if (!Platform.isAndroid) return true;
    try {
      if (await FlutterOverlayWindow.isActive()) {
        KazumiLogger().i('McpOverlay: 悬浮窗已存在，跳过');
        return true;
      }
      await FlutterOverlayWindow.showOverlay(
        height: 52,
        width: 240,
        alignment: OverlayAlignment.topRight,
        enableDrag: true,
        positionGravity: PositionGravity.auto,
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        overlayTitle: '樱花动漫 MCP',
        overlayContent: 'MCP 悬浮快捷开关',
      );
      KazumiLogger().i('McpOverlay: showOverlay 调用成功');
      return true;
    } catch (e) {
      KazumiLogger().e('McpOverlay: 显示悬浮窗失败: $e');
      return false;
    }
  }

  /// 关闭悬浮窗。
  Future<void> hide() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterOverlayWindow.closeOverlay();
      KazumiLogger().i('McpOverlay: 悬浮窗已关闭');
    } catch (e) {
      KazumiLogger().e('McpOverlay: 关闭悬浮窗失败: $e');
    }
  }

  /// 把当前 MCP 状态广播给悬浮窗 UI。
  Future<void> broadcast() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterOverlayWindow.shareData({
        'action': 'mcp_status',
        'running': McpServer.instance.isRunning,
      });
    } catch (e) {
      KazumiLogger().e('McpOverlay: 广播状态失败: $e');
    }
  }
}

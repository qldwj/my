import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端窗口几何信息（位置/大小）记忆
///
/// - 窗口移动/缩放时自动保存（AppWidget 监听 windowManager 事件调用 [save]）
/// - 启动时在窗口显示前调用 [restore] 恢复
class WindowStateService {
  WindowStateService._();

  /// 保存当前窗口位置和大小
  static Future<void> save() async {
    try {
      if (!GStorage.getSetting(SettingsKeys.windowRememberGeometry)) return;
      final position = await windowManager.getPosition();
      final size = await windowManager.getSize();
      final data = jsonEncode({
        'x': position.dx,
        'y': position.dy,
        'w': size.width,
        'h': size.height,
      });
      await GStorage.putSetting(SettingsKeys.windowGeometry, data);
    } catch (e) {
      KazumiLogger().w('WindowStateService: save failed', error: e);
    }
  }

  /// 恢复上次保存的窗口位置和大小（在 windowManager.show() 之前调用）
  static Future<void> restore() async {
    try {
      if (!GStorage.getSetting(SettingsKeys.windowRememberGeometry)) return;
      final raw = GStorage.getSetting(SettingsKeys.windowGeometry);
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final w = (decoded['w'] as num?)?.toDouble();
      final h = (decoded['h'] as num?)?.toDouble();
      final x = (decoded['x'] as num?)?.toDouble();
      final y = (decoded['y'] as num?)?.toDouble();
      if (w == null || h == null || w <= 0 || h <= 0) return;
      // 基本合法性检查：防止换显示器/分辨率后窗口跑到屏幕外或过大
      if (w > 6000 || h > 4000) return;
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      await windowManager.setSize(Size(w, h));
      KazumiLogger().i('WindowStateService: restored size=${w}x$h pos=${x ?? '-'},${y ?? '-'}');
    } catch (e) {
      KazumiLogger().w('WindowStateService: restore failed', error: e);
    }
  }
}

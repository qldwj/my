import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/device.dart';
import 'package:window_manager/window_manager.dart';

/// 全局快捷键（桌面端）
///
/// 当前注册：Ctrl + Alt + K → 显示/隐藏主窗口
/// 仅在 [SettingsKeys.globalHotkeyEnabled] 开启时生效。
///
/// 依赖 hotkey_manager ^0.2.x（HotKey 使用 `HotKeyModifier` 枚举，
/// `register` 返回 Future<void>）。
class GlobalHotkeyService {
  GlobalHotkeyService._();

  static HotKey? _hotKey;
  static bool _registered = false;

  /// 根据设置注册/注销全局快捷键
  static Future<void> apply() async {
    if (!isDesktop()) return;
    final enabled = GStorage.getSetting(SettingsKeys.globalHotkeyEnabled);
    if (enabled == _registered) return;
    if (!enabled) {
      await unregister();
      return;
    }
    try {
      _hotKey = HotKey(
        key: PhysicalKeyboardKey.keyK,
        modifiers: [
          HotKeyModifier.control,
          HotKeyModifier.alt,
        ],
        scope: HotKeyScope.system,
      );
      await hotKeyManager.register(
        _hotKey!,
        keyDownHandler: (hotKey) async {
          if (await windowManager.isVisible()) {
            await windowManager.hide();
          } else {
            await windowManager.show();
            await windowManager.focus();
          }
        },
      );
      _registered = true;
      KazumiLogger().i('GlobalHotkeyService: registered Ctrl+Alt+K');
    } catch (e) {
      _registered = false;
      KazumiLogger().w('GlobalHotkeyService: register failed', error: e);
    }
  }

  static Future<void> unregister() async {
    try {
      if (_hotKey != null) {
        await hotKeyManager.unregister(_hotKey!);
      }
    } catch (_) {}
    _hotKey = null;
    _registered = false;
  }
}

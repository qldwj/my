import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:yhdm/services/storage/storage.dart';

class TrayService {
  TrayService._();

  static bool _iconSet = false;

  static Future<void> initialize() async {
    // 尊重托盘开关（默认开启）
    if (!GStorage.getSetting(SettingsKeys.desktopTrayEnabled)) {
      return;
    }
    if (Platform.isWindows) {
      await trayManager.setIcon('assets/images/logo/logo_android.png');
    } else if (Platform.environment.containsKey('FLATPAK_ID') ||
        Platform.environment.containsKey('SNAP')) {
      await trayManager.setIcon('io.github.Predidit.Kazumi');
    } else {
      await trayManager.setIcon('assets/images/logo/logo_android.png');
    }
    _iconSet = true;

    if (!Platform.isLinux) {
      await trayManager.setToolTip('YHDM');
    }

    Menu trayMenu = Menu(items: [
      MenuItem(key: 'show_window', label: '显示窗口'),
      MenuItem.separator(),
      MenuItem(key: 'download', label: '打开下载页'),
      MenuItem(key: 'settings', label: '打开设置'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: '退出 YHDM')
    ]);
    await trayManager.setContextMenu(trayMenu);
  }

  /// Must run before exit(): the plugin only drops the Windows icon on
  /// WM_DESTROY, and its destroy assumes an icon was set.
  static Future<void> dispose() async {
    if (!_iconSet) return;
    _iconSet = false;
    await trayManager.destroy();
  }
}

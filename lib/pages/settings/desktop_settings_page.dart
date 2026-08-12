import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/settings_section_card.dart';
import 'package:kazumi/services/platform/global_hotkey_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/device.dart';

/// 桌面端设置页（托盘 / 窗口记忆 / 全局快捷键）
class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({super.key});

  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  bool _trayEnabled = true;
  bool _rememberGeometry = true;
  bool _hotkeyEnabled = false;

  @override
  void initState() {
    super.initState();
    _trayEnabled = GStorage.getSetting(SettingsKeys.desktopTrayEnabled);
    _rememberGeometry = GStorage.getSetting(SettingsKeys.windowRememberGeometry);
    _hotkeyEnabled = GStorage.getSetting(SettingsKeys.globalHotkeyEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(title: const Text('桌面端设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsSectionCard(
                title: '系统托盘',
                children: [
                  SwitchListTile(
                    title: const Text('启用系统托盘'),
                    subtitle: const Text('关闭后最小化/退出行为不受托盘影响'),
                    value: _trayEnabled,
                    onChanged: (value) async {
                      setState(() => _trayEnabled = value);
                      await GStorage.putSetting(
                          SettingsKeys.desktopTrayEnabled, value);
                      if (mounted) {
                        KazumiDialog.showToast(
                            message: value ? '托盘已启用（重启生效）' : '托盘已关闭（重启生效）');
                      }
                    },
                  ),
                ],
              ),
              SettingsSectionCard(
                title: '窗口',
                children: [
                  SwitchListTile(
                    title: const Text('记住窗口位置和大小'),
                    subtitle: const Text('下次启动恢复上次的窗口位置和大小'),
                    value: _rememberGeometry,
                    onChanged: (value) async {
                      setState(() => _rememberGeometry = value);
                      await GStorage.putSetting(
                          SettingsKeys.windowRememberGeometry, value);
                    },
                  ),
                ],
              ),
              SettingsSectionCard(
                title: '全局快捷键',
                children: [
                  SwitchListTile(
                    title: const Text('启用全局快捷键'),
                    subtitle: const Text('Ctrl + Alt + K 显示/隐藏主窗口（需重启生效）'),
                    value: _hotkeyEnabled,
                    onChanged: (value) async {
                      setState(() => _hotkeyEnabled = value);
                      await GStorage.putSetting(
                          SettingsKeys.globalHotkeyEnabled, value);
                      // 立即生效（注册或注销）
                      await GlobalHotkeyService.apply();
                    },
                  ),
                  if (!isDesktop())
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '该页面仅桌面端（Windows / macOS / Linux）生效。',
                        style: TextStyle(
                            fontSize: 12, color: colorScheme.outline),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

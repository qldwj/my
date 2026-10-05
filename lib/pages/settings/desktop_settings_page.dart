import 'package:flutter/material.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/widget/settings_section_card.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/services/platform/global_hotkey_service.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/utils/device.dart';

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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SysAppBar(title: Text(l10n.setADesktopSettings)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsSectionCard(
                title: l10n.setASystemTray,
                children: [
                  SwitchListTile(
                    title: Text(l10n.setAEnableTray),
                    subtitle: Text(l10n.setAEnableTrayDesc),
                    value: _trayEnabled,
                    onChanged: (value) async {
                      setState(() => _trayEnabled = value);
                      await GStorage.putSetting(
                          SettingsKeys.desktopTrayEnabled, value);
                      if (mounted) {
                        KazumiDialog.showToast(
                            message: value
                                ? AppLocalizations.of(context)!.setATrayEnabledRestart
                                : AppLocalizations.of(context)!.setATrayDisabledRestart);
                      }
                    },
                  ),
                ],
              ),
              SettingsSectionCard(
                title: l10n.setAWindow,
                children: [
                  SwitchListTile(
                    title: Text(l10n.setARememberGeometry),
                    subtitle: Text(l10n.setARememberGeometryDesc),
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
                title: l10n.setAGlobalHotkey,
                children: [
                  SwitchListTile(
                    title: Text(l10n.setAEnableHotkey),
                    subtitle: Text(l10n.setAHotkeyDesc),
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
                        l10n.setADesktopOnlyNote,
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

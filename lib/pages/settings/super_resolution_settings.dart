import 'package:flutter/material.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/pages/player/controller/player_super_resolution.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:card_settings_ui/card_settings_ui.dart';

class SuperResolutionSettings extends StatefulWidget {
  const SuperResolutionSettings({super.key});

  @override
  State<SuperResolutionSettings> createState() =>
      _SuperResolutionSettingsState();
}

class _SuperResolutionSettingsState extends State<SuperResolutionSettings> {
  late bool disableWarning;
  late SuperResolutionMode superResolutionMode;

  @override
  void initState() {
    super.initState();
    disableWarning = GStorage.getSetting<bool>(
      SettingsKeys.disableSuperResolutionWarning,
    );
    superResolutionMode = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting<int>(SettingsKeys.defaultSuperResolutionMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SysAppBar(
        title: Text(l10n.setASuperResolution),
      ),
      body: SettingsList(
        maxWidth: 1000,
        sections: [
          SettingsSection(
              title: Text(l10n.setASrHint,
                  style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                for (final mode in SuperResolutionMode.values)
                  SettingsTile<SuperResolutionMode>.radioTile(
                    title: Text(
                      mode.label,
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                    description: Text(
                      mode.description,
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                    radioValue: mode,
                    groupValue: superResolutionMode,
                    onChanged: (SuperResolutionMode? value) {
                      if (value == null) return;
                      GStorage.putSetting<int>(
                        SettingsKeys.defaultSuperResolutionMode,
                        value.storageValue,
                      );
                      setState(() {
                        superResolutionMode = value;
                      });
                    },
                  ),
              ]),
          SettingsSection(
            title: Text(l10n.setADefaultBehavior, style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.switchTile(
                title: Text(l10n.setADisableSrWarning, style: TextStyle(fontFamily: fontFamily)),
                description: Text(l10n.setADisableSrWarningDesc,
                    style: TextStyle(fontFamily: fontFamily)),
                initialValue: disableWarning,
                onToggle: (value) async {
                  disableWarning = value ?? !disableWarning;
                  await GStorage.putSetting<bool>(
                    SettingsKeys.disableSuperResolutionWarning,
                    disableWarning,
                  );
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

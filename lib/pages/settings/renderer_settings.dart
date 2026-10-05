import 'package:flutter/material.dart';
import 'package:yhdm/bean/settings/settings_detail_scaffold.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/utils/constants.dart';
import 'package:yhdm/bean/settings/settings_list.dart';

class RendererSettings extends StatefulWidget {
  const RendererSettings({super.key});

  @override
  State<RendererSettings> createState() => _RendererSettingsState();
}

class _RendererSettingsState extends State<RendererSettings> {
  late String _renderer =
      GStorage.getSetting(SettingsKeys.androidVideoRenderer);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsDetailScaffold(
      title: Text(l10n.setARenderer),
      body: SettingsList(
        sections: [
          SettingsRadioSection<String>(
            title: Text(l10n.setARendererPickHint),
            groupValue: _renderer,
            onChanged: (String? value) {
              if (value != null) {
                GStorage.putSetting<String>(
                    SettingsKeys.androidVideoRenderer, value);
                setState(() {
                  _renderer = value;
                });
              }
            },
            tiles: androidVideoRenderersList.entries
                .map((e) => SettingsTile<String>.radioTile(
                      title: Text(e.key),
                      description: Text(e.value),
                      radioValue: e.key,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

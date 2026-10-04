import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/network/image_acceleration.dart';
import 'package:kazumi/services/storage/storage.dart';

class NetworkMirrorSettings extends StatefulWidget {
  const NetworkMirrorSettings({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  State<NetworkMirrorSettings> createState() => _NetworkMirrorSettingsState();
}

class _NetworkMirrorSettingsState extends State<NetworkMirrorSettings> {
  Future<void> _save<T>(SettingKey<T> key, T value) async {
    await GStorage.putSetting(key, value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bangumiAcceleration = BangumiAcceleration.current;
    final gitProxy = GStorage.getSetting(SettingsKeys.enableGitProxy);
    final imageAcceleration = ImageAcceleration.fromSetting(
      GStorage.getSetting(SettingsKeys.imageAcceleration),
    );
    return SettingsSection(
      title: Text(l10n.setDMirrorTitle),
      margin: widget.margin,
      tiles: [
        SettingsTile(
          leading: Icons.travel_explore_rounded,
          title: Text(l10n.setDBangumiItemAccel),
          description: Text(l10n.setDBangumiItemAccelDesc),
          value: SizedBox(
            width: 60,
            child: Text(
              bangumiAcceleration.label(l10n),
              textAlign: TextAlign.center,
            ),
          ),
          onPressed: (context) => _selectAcceleration(
            context,
            title: l10n.setDBangumiItemAccel,
            current: bangumiAcceleration,
            modes: BangumiAcceleration.values,
            label: (mode) => mode.label(l10n),
            description: (mode) => mode.description(l10n),
            setting: SettingsKeys.bangumiAcceleration,
          ),
        ),
        SettingsTile.switchTile(
          leading: Icons.extension_rounded,
          title: Text(l10n.setDRuleRepoMirror),
          description: Text(l10n.setDRuleRepoMirrorDesc),
          initialValue: gitProxy,
          onToggle: (value) =>
              _save(SettingsKeys.enableGitProxy, value ?? !gitProxy),
        ),
        SettingsTile(
          leading: Icons.image_rounded,
          title: Text(l10n.setCImageAcceleration),
          description: Text(l10n.setCImageAccelerationDesc),
          value: SizedBox(
            // Match the trailing Material 3 switch width.
            width: 60,
            child: Text(
              imageAcceleration.label(l10n),
              textAlign: TextAlign.center,
            ),
          ),
          onPressed: (context) => _selectAcceleration(
            context,
            title: l10n.setCImageAcceleration,
            current: imageAcceleration,
            modes: ImageAcceleration.values,
            label: (mode) => mode.label(l10n),
            description: (mode) => mode.description(l10n),
            setting: SettingsKeys.imageAcceleration,
          ),
        ),
      ],
    );
  }

  Future<void> _selectAcceleration<T extends Enum>(
    BuildContext context, {
    required String title,
    required T current,
    required List<T> modes,
    required String Function(T) label,
    required String Function(T) description,
    required SettingKey<String> setting,
  }) async {
    final selected = await KazumiDialog.show<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: current,
            onChanged: (value) => Navigator.of(context).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in modes)
                  RadioListTile<T>(
                    value: mode,
                    title: Text(label(mode)),
                    subtitle: Text(
                      description(mode),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (mounted && selected != null && selected != current) {
      await _save(setting, selected.name);
    }
  }
}

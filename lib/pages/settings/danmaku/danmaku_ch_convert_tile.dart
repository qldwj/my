import 'package:flutter/material.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/settings/settings_dropdown_tile.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/modules/danmaku/danmaku_ch_convert.dart';
import 'package:yhdm/services/storage/storage.dart';

extension _ConversionLabel on DanmakuChConvert {
  String label(AppLocalizations l10n) => switch (this) {
        DanmakuChConvert.none => l10n.setBChConvertNone,
        DanmakuChConvert.simplified => l10n.setBChConvertToSimplified,
        DanmakuChConvert.traditional => l10n.setBChConvertToTraditional,
      };
}

class DanmakuChConvertTile extends StatefulWidget {
  const DanmakuChConvertTile({super.key});

  @override
  State<DanmakuChConvertTile> createState() => _DanmakuChConvertTileState();
}

class _DanmakuChConvertTileState extends State<DanmakuChConvertTile> {
  late final _settingsChanges = GStorage.watchSettings([
    SettingsKeys.danmakuChConvert,
  ]);
  bool _saving = false;

  Future<void> _selectMode(DanmakuChConvert mode) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await GStorage.putSetting(SettingsKeys.danmakuChConvert, mode.value);
    } catch (_) {
      if (mounted) {
        KazumiDialog.showToast(
            context: context, message: AppLocalizations.of(context)!.setBChConvertSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<void>(
      stream: _settingsChanges,
      builder: (context, _) {
        final mode = DanmakuChConvert.fromValue(
          GStorage.getSetting(SettingsKeys.danmakuChConvert),
        );
        return SettingsDropdownTile<DanmakuChConvert>(
          leading: Icons.translate_rounded,
          title: Text(l10n.setBChConvert),
          description: Text(l10n.setBChConvertDesc),
          enabled: !_saving,
          value: mode,
          options: {
            for (final option in DanmakuChConvert.values) option: option.label(l10n),
          },
          onChanged: _selectMode,
        );
      },
    );
  }
}

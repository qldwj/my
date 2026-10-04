import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/widget/split_list_row.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/services/network/metered_network_service.dart';
import 'package:kazumi/services/player/low_memory_mode.dart';

class LowMemoryModeSettingsTile extends StatelessWidget {
  const LowMemoryModeSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _ModeBuilder(builder: (context, mode, isMetered) {
      return SettingsTile(
        leading: Icons.data_saver_on_rounded,
        title: Text(l10n.setALowMemoryMode),
        description: Text(mode.statusDescription(l10n, isMetered)),
        value: Text(mode.label(l10n)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onPressed: (_) => KazumiDialog.show<void>(
          builder: (_) => const _LowMemoryModeDialog(),
        ),
      );
    });
  }
}

class _LowMemoryModeDialog extends StatefulWidget {
  const _LowMemoryModeDialog();

  @override
  State<_LowMemoryModeDialog> createState() => _LowMemoryModeDialogState();
}

class _LowMemoryModeDialogState extends State<_LowMemoryModeDialog> {
  bool _saving = false;

  Future<void> _selectMode(LowMemoryMode? mode) async {
    if (mode == null || _saving) return;
    setState(() => _saving = true);
    try {
      await mode.save();
      if (!mounted) return;
      KazumiDialog.dismiss(context: context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      KazumiDialog.showToast(context: context, message: AppLocalizations.of(context)!.setASaveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(l10n.setALowMemoryMode),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: _ModeBuilder(builder: (context, mode, isMetered) {
          final enabled = mode.isEnabled(isMetered: isMetered);
          final foreground =
              enabled ? colors.onSecondaryContainer : colors.onSurfaceVariant;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: enabled
                        ? colors.secondaryContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        enabled
                            ? Icons.data_saver_on_rounded
                            : Icons.data_usage_rounded,
                        color: foreground,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          mode.statusDescription(l10n, isMetered),
                          style: textTheme.bodyMedium?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              RadioGroup<LowMemoryMode>(
                groupValue: mode,
                onChanged: _selectMode,
                child: SplitListGroup(
                  children: [
                    for (final option in LowMemoryMode.values)
                      SettingsTile<LowMemoryMode>.radioTile(
                        title: Text(option == LowMemoryMode.auto
                            ? l10n.setAModeDefault(label: option.label(l10n))
                            : option.label(l10n)),
                        description: Text(option.description(l10n)),
                        radioValue: option,
                        enabled: !_saving,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.setALmmFootnote,
                style: textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          );
        }),
      ),
      actions: [
        TextButton(
          onPressed: () => KazumiDialog.dismiss(context: context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

class _ModeBuilder extends StatefulWidget {
  const _ModeBuilder({required this.builder});

  final Widget Function(BuildContext, LowMemoryMode, bool) builder;

  @override
  State<_ModeBuilder> createState() => _ModeBuilderState();
}

extension _ModePresentation on LowMemoryMode {
  String label(AppLocalizations l10n) => switch (this) {
        LowMemoryMode.auto => l10n.setALmmAuto,
        LowMemoryMode.always => l10n.setALmmAlways,
        LowMemoryMode.never => l10n.setALmmNever,
      };

  String description(AppLocalizations l10n) => switch (this) {
        LowMemoryMode.auto => l10n.setALmmAutoDesc,
        LowMemoryMode.always => l10n.setALmmAlwaysDesc,
        LowMemoryMode.never => l10n.setALmmNeverDesc,
      };

  String statusDescription(AppLocalizations l10n, bool isMetered) => switch (this) {
        LowMemoryMode.auto =>
          isMetered ? l10n.setALmmStatusAutoOn : l10n.setALmmStatusAutoOff,
        LowMemoryMode.always => l10n.setALmmStatusAlwaysOn,
        LowMemoryMode.never =>
          isMetered ? l10n.setALmmStatusNeverMetered : l10n.setALmmStatusNever,
      };
}

class _ModeBuilderState extends State<_ModeBuilder> {
  late final Stream<void> _settingsChanges = LowMemoryMode.watch();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: _settingsChanges,
      builder: (context, _) => ValueListenableBuilder<bool>(
        valueListenable: MeteredNetworkService.listenable,
        builder: (context, isMetered, _) =>
            widget.builder(context, LowMemoryMode.current, isMetered),
      ),
    );
  }
}

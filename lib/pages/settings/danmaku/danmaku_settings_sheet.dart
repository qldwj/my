import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:yhdm/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:yhdm/bean/dialog/material_bottom_sheet.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/pages/settings/danmaku/danmaku_shield_settings_sheet.dart';
import 'package:yhdm/pages/settings/danmaku/danmaku_time_offset_sheet.dart';
import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/utils/device.dart';

enum _DanmakuSettingsDestination {
  timeOffset,
}

Future<void> showDanmakuSettingsSheet({
  required BuildContext context,
  required DanmakuController danmakuController,
  VoidCallback? onUpdateDanmakuSpeed,
  VoidCallback? onTimelineOffsetChanged,
}) async {
  final destination =
      await showAdaptiveBottomSheet<_DanmakuSettingsDestination>(
    context: context,
    builder: (context) {
      return _DanmakuSettingsSheet(
        danmakuController: danmakuController,
        onUpdateDanmakuSpeed: onUpdateDanmakuSpeed,
      );
    },
  );

  if (!context.mounted ||
      destination != _DanmakuSettingsDestination.timeOffset) {
    return;
  }

  await showAdaptiveBottomSheet<void>(
    context: context,
    builder: (context) {
      return DanmakuTimeOffsetSheet(
        onTimelineOffsetChanged: onTimelineOffsetChanged,
      );
    },
  );
}

class _DanmakuSettingsSheet extends StatefulWidget {
  final DanmakuController danmakuController;
  final VoidCallback? onUpdateDanmakuSpeed;

  const _DanmakuSettingsSheet({
    required this.danmakuController,
    this.onUpdateDanmakuSpeed,
  });

  @override
  State<_DanmakuSettingsSheet> createState() => _DanmakuSettingsSheetState();
}

class _DanmakuSettingsSheetState extends State<_DanmakuSettingsSheet> {
  void _showDanmakuShieldSheet() {
    showAdaptiveBottomSheet<void>(
      context: context,
      builder: (context) => const DanmakuShieldSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      bottom: false,
      child: Scaffold(
        body: Column(
          children: [
            MaterialBottomSheetHeader(
              title: l10n.danmakuSettings,
              description: l10n.setBSheetAdjustDesc,
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SettingsList(
                sections: [
                  SettingsSection(
                    title:
                        Text(l10n.setBDanmakuFilter, style: TextStyle(fontFamily: fontFamily)),
                    tiles: [
                      SettingsTile.navigation(
                        onPressed: (_) {
                          _showDanmakuShieldSheet();
                        },
                        title: Text(l10n.setBKeywordFilter,
                            style: TextStyle(fontFamily: fontFamily)),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title:
                        Text(l10n.setBDanmakuStyle, style: TextStyle(fontFamily: fontFamily)),
                    tiles: [
                      SettingsTile(
                        title: Text(l10n.setBFontSize,
                            style: TextStyle(fontFamily: fontFamily)),
                        description: Slider(
                          value: widget.danmakuController.option.fontSize,
                          min: 10,
                          max: isCompact() ? 32 : 48,
                          label:
                              '${widget.danmakuController.option.fontSize.floorToDouble()}',
                          onChanged: (value) {
                            setState(
                                () => widget.danmakuController.updateOption(
                                      widget.danmakuController.option.copyWith(
                                        fontSize: value.floorToDouble(),
                                      ),
                                    ));
                            GStorage.putSetting<double>(
                                SettingsKeys.danmakuFontSize,
                                value.floorToDouble());
                          },
                        ),
                      ),
                      SettingsTile(
                        title: Text(l10n.setBDanmakuOpacity,
                            style: TextStyle(fontFamily: fontFamily)),
                        description: Slider(
                          value: widget.danmakuController.option.opacity,
                          min: 0.1,
                          max: 1,
                          label:
                              '${(widget.danmakuController.option.opacity * 100).round()}%',
                          onChanged: (value) {
                            setState(
                                () => widget.danmakuController.updateOption(
                                      widget.danmakuController.option.copyWith(
                                        opacity: value,
                                      ),
                                    ));
                            GStorage.putSetting<double>(
                                SettingsKeys.danmakuOpacity,
                                double.parse(value.toStringAsFixed(2)));
                          },
                        ),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title:
                        Text(l10n.setBDanmakuDisplay, style: TextStyle(fontFamily: fontFamily)),
                    tiles: [
                      SettingsTile.navigation(
                        onPressed: (context) {
                          Navigator.of(context)
                              .pop(_DanmakuSettingsDestination.timeOffset);
                        },
                        title: Text(l10n.setBTimelineOffset,
                            style: TextStyle(fontFamily: fontFamily)),
                        value: Text(
                          formatDanmakuTimeOffset(
                            l10n,
                            normalizeDanmakuTimeOffset(
                              GStorage.getSetting<double>(
                                  SettingsKeys.danmakuTimeOffset),
                            ),
                          ),
                          style: TextStyle(fontFamily: fontFamily),
                        ),
                      ),
                      SettingsTile(
                        title: Text(l10n.setBDanmakuArea,
                            style: TextStyle(fontFamily: fontFamily)),
                        description: Slider(
                          value: widget.danmakuController.option.area,
                          min: 0,
                          max: 1,
                          divisions: 8,
                          label:
                              '${(widget.danmakuController.option.area * 100).round()}%',
                          onChanged: (value) {
                            setState(
                                () => widget.danmakuController.updateOption(
                                      widget.danmakuController.option.copyWith(
                                        area: value,
                                      ),
                                    ));
                            GStorage.putSetting<double>(
                                SettingsKeys.danmakuArea, value);
                          },
                        ),
                      ),
                      SettingsTile(
                        title: Text(l10n.setBDurationShort,
                            style: TextStyle(fontFamily: fontFamily)),
                        description: Slider(
                          value: widget.danmakuController.option.duration
                              .toDouble(),
                          min: 2,
                          max: 16,
                          divisions: 14,
                          label:
                              '${widget.danmakuController.option.duration.round()}',
                          onChanged: (value) {
                            setState(
                                () => widget.danmakuController.updateOption(
                                      widget.danmakuController.option.copyWith(
                                        duration: value,
                                      ),
                                    ));
                            GStorage.putSetting<double>(
                                SettingsKeys.danmakuDuration,
                                value.round().toDouble());
                          },
                        ),
                      ),
                      SettingsTile(
                        title: Text(l10n.setBLineHeightShort,
                            style: TextStyle(fontFamily: fontFamily)),
                        description: Slider(
                          value: widget.danmakuController.option.lineHeight,
                          min: 0,
                          max: 3,
                          divisions: 30,
                          label: widget.danmakuController.option.lineHeight
                              .toStringAsFixed(1),
                          onChanged: (value) {
                            setState(() =>
                                widget.danmakuController.updateOption(
                                  widget.danmakuController.option.copyWith(
                                    lineHeight:
                                        double.parse(value.toStringAsFixed(1)),
                                  ),
                                ));
                            GStorage.putSetting<double>(
                                SettingsKeys.danmakuLineHeight,
                                double.parse(value.toStringAsFixed(1)));
                          },
                        ),
                      ),
                      SettingsTile.switchTile(
                        onToggle: (value) {
                          bool show =
                              value ?? widget.danmakuController.option.hideTop;
                          setState(() => widget.danmakuController.updateOption(
                                widget.danmakuController.option.copyWith(
                                  hideTop: !show,
                                ),
                              ));
                          GStorage.putSetting<bool>(
                              SettingsKeys.danmakuTop, show);
                        },
                        title: Text(l10n.setBTopDanmaku,
                            style: TextStyle(fontFamily: fontFamily)),
                        initialValue: !widget.danmakuController.option.hideTop,
                      ),
                      SettingsTile.switchTile(
                        onToggle: (value) {
                          bool show = value ??
                              widget.danmakuController.option.hideBottom;
                          setState(() => widget.danmakuController.updateOption(
                                widget.danmakuController.option.copyWith(
                                  hideBottom: !show,
                                ),
                              ));
                          GStorage.putSetting<bool>(
                              SettingsKeys.danmakuBottom, show);
                        },
                        title: Text(l10n.setBBottomDanmaku,
                            style: TextStyle(fontFamily: fontFamily)),
                        initialValue:
                            !widget.danmakuController.option.hideBottom,
                      ),
                      SettingsTile.switchTile(
                        onToggle: (value) {
                          bool show = value ??
                              widget.danmakuController.option.hideScroll;
                          setState(() => widget.danmakuController.updateOption(
                                widget.danmakuController.option.copyWith(
                                  hideScroll: !show,
                                ),
                              ));
                          GStorage.putSetting<bool>(
                              SettingsKeys.danmakuScroll, show);
                        },
                        title: Text(l10n.setBScrollDanmaku,
                            style: TextStyle(fontFamily: fontFamily)),
                        initialValue:
                            !widget.danmakuController.option.hideScroll,
                      ),
                      SettingsTile.switchTile(
                        onToggle: (value) {
                          bool followSpeed = value ??
                              !GStorage.getSetting<bool>(
                                  SettingsKeys.danmakuFollowSpeed);
                          GStorage.putSetting<bool>(
                              SettingsKeys.danmakuFollowSpeed, followSpeed);
                          widget.onUpdateDanmakuSpeed?.call();
                          setState(() {});
                        },
                        title: Text(l10n.setBFollowSpeedShort,
                            style: TextStyle(fontFamily: fontFamily)),
                        description: Text(l10n.setBFollowSpeedShortDesc,
                            style: TextStyle(fontFamily: fontFamily)),
                        initialValue: GStorage.getSetting<bool>(
                            SettingsKeys.danmakuFollowSpeed),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

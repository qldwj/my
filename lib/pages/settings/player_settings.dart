import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/settings/settings_dropdown_tile.dart';
import 'package:yhdm/bean/settings/settings_list.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/pages/player/controller/player_aspect_ratio.dart';
import 'package:yhdm/utils/constants.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/player/pip_utils.dart';
import 'package:yhdm/services/player/skip_segments_service.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/utils/device.dart';

class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  State<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  static const double _minPlayerControllerLayerDisappearSeconds = 1;
  static const double _maxPlayerControllerLayerDisappearSeconds = 10;
  static const int _playerControllerLayerDisappearDivisions = 18;

  late double defaultPlaySpeed;
  late double defaultShortcutForwardPlaySpeed;
  late PlayerAspectRatio defaultAspectRatioMode;
  late bool hAenable;
  late bool androidEnableOpenSLES;
  late bool androidAutoEnterPIP;
  late bool lowMemoryMode;
  late bool playResume;
  late bool playSpeedMemory;
  late bool showPlayerError;
  late bool privateMode;
  late bool playerDebugMode;
  late bool playerDisableAnimations;
  late bool forceAdBlocker;
  late bool autoPlayNext;
  late bool preloadNextEpisode;
  late bool nightEye;
  late bool autoSource;
  late bool fullBuffer;
  late bool autoSwitchSource;
  late int skipOpDefault;
  late int skipEdDefault;
  late bool autoSkipOpEd;
  late bool backgroundPlayback;
  late bool brightnessVolumeGesture;
  late bool showLastWatchCard;
  late int playerButtonSkipTime;
  late int playerArrowKeySkipTime;
  late int playerLogLevel;
  late int playerControllerLayerDisappearTime;

  /// 格式化秒数为 X分X秒
  String _formatDuration(int seconds) {
    final l10n = AppLocalizations.of(context)!;
    if (seconds == 0) return l10n.setADurZero;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes == 0) {
      return l10n.setADurSec(seconds: remainingSeconds);
    } else if (remainingSeconds == 0) {
      return l10n.setADurMin(minutes: minutes);
    } else {
      return l10n.setADurMinSec(minutes: minutes, seconds: remainingSeconds);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettingsFromStorage();
  }

  void _loadSettingsFromStorage() {
    defaultPlaySpeed =
        GStorage.getSetting<double>(SettingsKeys.defaultPlaySpeed);
    defaultShortcutForwardPlaySpeed = GStorage.getSetting<double>(
        SettingsKeys.defaultShortcutForwardPlaySpeed);
    defaultAspectRatioMode = PlayerAspectRatio.fromStorageValue(
      GStorage.getSetting<int>(SettingsKeys.defaultAspectRatioType),
    );
    hAenable = GStorage.getSetting<bool>(SettingsKeys.hAenable);
    androidEnableOpenSLES =
        GStorage.getSetting<bool>(SettingsKeys.androidEnableOpenSLES);
    androidAutoEnterPIP =
        GStorage.getSetting<bool>(SettingsKeys.androidAutoEnterPIP);
    lowMemoryMode = GStorage.getSetting<bool>(SettingsKeys.lowMemoryMode);
    playResume = GStorage.getSetting<bool>(SettingsKeys.playResume);
    privateMode = GStorage.getSetting<bool>(SettingsKeys.privateMode);
    showPlayerError = GStorage.getSetting<bool>(SettingsKeys.showPlayerError);
    playerDebugMode = GStorage.getSetting<bool>(SettingsKeys.playerDebugMode);
    autoPlayNext = GStorage.getSetting<bool>(SettingsKeys.autoPlayNext);
    playSpeedMemory =
        GStorage.getSetting<bool>(SettingsKeys.playSpeedMemoryEnabled);
    preloadNextEpisode =
        GStorage.getSetting<bool>(SettingsKeys.preloadNextEpisode);
    nightEye = GStorage.getSetting<bool>(SettingsKeys.nightEyeProtection);
    autoSource = GStorage.getSetting<bool>(SettingsKeys.autoSelectSource);
    fullBuffer = GStorage.getSetting<bool>(SettingsKeys.fullBuffer);
    autoSwitchSource =
        GStorage.getSetting<bool>(SettingsKeys.autoSwitchSource);
    skipOpDefault =
        GStorage.getSetting<int>(SettingsKeys.skipOpDefaultSeconds);
    skipEdDefault =
        GStorage.getSetting<int>(SettingsKeys.skipEdDefaultSeconds);
    autoSkipOpEd =
        GStorage.getSetting<bool>(SettingsKeys.autoSkipOpEdEnabled);
    backgroundPlayback =
        GStorage.getSetting<bool>(SettingsKeys.backgroundPlayback);
    playerDisableAnimations =
        GStorage.getSetting<bool>(SettingsKeys.playerDisableAnimations);
    forceAdBlocker = GStorage.getSetting<bool>(SettingsKeys.forceAdBlocker);
    playerLogLevel = GStorage.getSetting<int>(SettingsKeys.playerLogLevel);

    brightnessVolumeGesture =
        GStorage.getSetting<bool>(SettingsKeys.brightnessVolumeGesture);

    showLastWatchCard =
        GStorage.getSetting<bool>(SettingsKeys.showLastWatchCard);

    playerButtonSkipTime =
        GStorage.getSetting<int>(SettingsKeys.buttonSkipTime);
    playerArrowKeySkipTime =
        GStorage.getSetting<int>(SettingsKeys.arrowKeySkipTime);

    playerControllerLayerDisappearTime = GStorage.getSetting<int>(
        SettingsKeys.playerControllerLayerDisappearTime);
  }

  Future<void> resetPlayerSettings() async {
    final l10n = AppLocalizations.of(context)!;
    final bool shouldReset = await KazumiDialog.show<bool>(
          builder: (context) => AlertDialog(
            title: Text(l10n.setAResetPlaybackTitle),
            content: Text(l10n.setAResetPlaybackDesc),
            actions: [
              TextButton(
                onPressed: () => KazumiDialog.dismiss(popWith: false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => KazumiDialog.dismiss(popWith: true),
                child: Text(l10n.setAResetPlaybackAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldReset) return;

    await GStorage.resetPlayerSettings();
    if (Platform.isAndroid) {
      await PipUtils.setAndroidAutoEnterPIPEnabled(false);
    }
    if (!mounted) return;
    setState(_loadSettingsFromStorage);
    KazumiDialog.showToast(message: l10n.setAResetPlaybackDone);
  }

  void onBackPressed(BuildContext context) {
    if (KazumiDialog.observer.hasKazumiDialog) {
      KazumiDialog.dismiss();
      return;
    }
  }

  void updateDefaultPlaySpeed(double speed) {
    GStorage.putSetting<double>(SettingsKeys.defaultPlaySpeed, speed);
    setState(() {
      defaultPlaySpeed = speed;
    });
  }

  void updateDefaultShortcutForwardPlaySpeed(double speed) {
    GStorage.putSetting<double>(
        SettingsKeys.defaultShortcutForwardPlaySpeed, speed);
    setState(() {
      defaultShortcutForwardPlaySpeed = speed;
    });
  }

  void updatePlayerLogLevel(int level) {
    GStorage.putSetting<int>(SettingsKeys.playerLogLevel, level);
    setState(() {
      playerLogLevel = level;
    });
  }

  void updateDefaultAspectRatioMode(PlayerAspectRatio mode) {
    GStorage.putSetting<int>(
      SettingsKeys.defaultAspectRatioType,
      mode.storageValue,
    );
    setState(() {
      defaultAspectRatioMode = mode;
    });
  }

  Future<void> updateButtonSkipTime() async {
    final l10n = AppLocalizations.of(context)!;
    final int? newButtonSkipTime = await _showSkipTimeChangeDialog(
        title: l10n.setAButtonSkipTimeTitle, initialValue: playerButtonSkipTime.toString());

    if (newButtonSkipTime != null &&
        newButtonSkipTime != playerButtonSkipTime) {
      GStorage.putSetting<int>(SettingsKeys.buttonSkipTime, newButtonSkipTime);
      setState(() {
        playerButtonSkipTime = newButtonSkipTime;
      });
    }
  }

  Future<int?> _showSkipTimeChangeDialog(
      {required String title, required String initialValue}) async {
    return KazumiDialog.show<int>(builder: (context) {
      final l10n = AppLocalizations.of(context)!;
      String input = "";
      return AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
          return TextField(
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              floatingLabelBehavior:
                  FloatingLabelBehavior.never,
              labelText: initialValue,
            ),
            onChanged: (value) {
              input = value;
            },
          );
        }),
        actions: <Widget>[
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () async {
              final int? newValue = int.tryParse(input);

              if (newValue == null) {
                KazumiDialog.showToast(message: l10n.setAEnterNumber);
                return;
              }

              if (newValue <= 0) {
                KazumiDialog.showToast(message: l10n.setAEnterNumberPositive);
                return;
              }
              KazumiDialog.dismiss(popWith: newValue);
            },
            child: Text(l10n.setAOk),
          ),
        ],
      );
    });
  }

  double get playerControllerLayerDisappearSeconds =>
      (playerControllerLayerDisappearTime / Duration.millisecondsPerSecond)
          .clamp(_minPlayerControllerLayerDisappearSeconds,
              _maxPlayerControllerLayerDisappearSeconds)
          .toDouble();

  String formatPlayerControllerLayerDisappearSeconds(double seconds) {
    final l10n = AppLocalizations.of(context)!;
    if (seconds == seconds.roundToDouble()) {
      return l10n.setADecimalSeconds(seconds: seconds.toDouble());
    }
    return l10n.setADecimalSeconds(seconds: double.parse(seconds.toStringAsFixed(1)));
  }

  void updatePlayerControllerLayerDisappearSeconds(double seconds) {
    final int newDisappearTime =
        (seconds * Duration.millisecondsPerSecond).round();
    if (newDisappearTime == playerControllerLayerDisappearTime) {
      return;
    }
    GStorage.putSetting<int>(
        SettingsKeys.playerControllerLayerDisappearTime, newDisappearTime);
    setState(() {
      playerControllerLayerDisappearTime = newDisappearTime;
    });
  }

  /// 全局默认片头/片尾时长设置对话框（0 = 不跳过）
  Future<void> _showDefaultSkipDialog({required bool isOp}) async {
    var value = (isOp ? skipOpDefault : skipEdDefault)
        .toDouble()
        .clamp(0.0, 300.0);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final l10n = AppLocalizations.of(ctx)!;
          return AlertDialog(
          title: Text(isOp ? l10n.setASkipOpTitle : l10n.setASkipEdTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatDuration(value.round()),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Slider(
                value: value,
                max: 300,
                divisions: 60,
                label: _formatDuration(value.round()),
                onChanged: (v) => setDialogState(() => value = v),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.setASkipGlobalHint,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final sec = value.round();
                if (isOp) {
                  skipOpDefault = sec;
                  GStorage.putSetting(SettingsKeys.skipOpDefaultSeconds, sec);
                } else {
                  skipEdDefault = sec;
                  GStorage.putSetting(SettingsKeys.skipEdDefaultSeconds, sec);
                }
                Navigator.pop(ctx);
                setState(() {});
                final durationText = _formatDuration(sec);
                KazumiDialog.showToast(
                    message: isOp
                        ? l10n.setASkipOpDefaultSet(duration: durationText)
                        : l10n.setASkipEdDefaultSet(duration: durationText));
              },
              child: Text(l10n.setAOk),
            ),
          ],
        );
        },
      ),
    );
  }

  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: SysAppBar(title: Text(l10n.playbackSettings)),
        body: SettingsList(
          maxWidth: 1000,
          sections: [
            SettingsSection(
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    showLastWatchCard = value ?? !showLastWatchCard;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.showLastWatchCard, showLastWatchCard);
                    setState(() {});
                  },
                  title: Row(
                    children: [
                      Icon(Icons.play_circle_fill_rounded,
                          size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(l10n.setAShowLastWatchCard,
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  description: Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(l10n.setAShowLastWatchCardDesc,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        )),
                  ),
                  initialValue: showLastWatchCard,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    hAenable = value ?? !hAenable;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.hAenable, hAenable);
                    setState(() {});
                  },
                  title: Text(l10n.setAHwDecode, style: TextStyle(fontFamily: fontFamily)),
                  initialValue: hAenable,
                ),
                SettingsTile(
                  onPressed: (_) async {
                    await context.pushNamed('/settings/player/decoder');
                  },
                  title:
                      Text(l10n.setAHwDecoder, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setAHwDecoderDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                if (Platform.isAndroid) ...[
                  SettingsTile(
                    onPressed: (_) async {
                      await context.pushNamed('/settings/player/renderer');
                    },
                    title:
                        Text(l10n.setARenderer, style: TextStyle(fontFamily: fontFamily)),
                    description: Text(l10n.setARendererDesc,
                        style: TextStyle(fontFamily: fontFamily)),
                  ),
                ],
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    lowMemoryMode = value ?? !lowMemoryMode;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.lowMemoryMode, lowMemoryMode);
                    setState(() {});
                  },
                  title:
                      Text(l10n.setALowMemoryMode, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setALowMemoryModeDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: lowMemoryMode,
                ),
                if (Platform.isAndroid) ...[
                  SettingsTile.switchTile(
                    onToggle: (value) async {
                      androidEnableOpenSLES = value ?? !androidEnableOpenSLES;
                      await GStorage.putSetting<bool>(
                          SettingsKeys.androidEnableOpenSLES,
                          androidEnableOpenSLES);
                      setState(() {});
                    },
                    title:
                        Text(l10n.setALowLatencyAudio, style: TextStyle(fontFamily: fontFamily)),
                    description: Text(l10n.setALowLatencyAudioDesc,
                        style: TextStyle(fontFamily: fontFamily)),
                    initialValue: androidEnableOpenSLES,
                  ),
                ],
                SettingsTile(
                  onPressed: (_) async {
                    context.pushNamed('/settings/player/super');
                  },
                  title: Text(l10n.setASuperResolution, style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setAPlaybackBehavior, style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    autoSource = value ?? !autoSource;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.autoSelectSource, autoSource);
                    setState(() {});
                  },
                  title: Text(l10n.setAAutoSelectSource,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setAAutoSelectSourceDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: autoSource,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    fullBuffer = value ?? !fullBuffer;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.fullBuffer, fullBuffer);
                    setState(() {});
                  },
                  title: Text('完整预缓冲',
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text('开启后持续缓冲直到视频下载完（内存占用高，建议仅在看长篇时开启）',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: fullBuffer,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    backgroundPlayback = value ?? !backgroundPlayback;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.backgroundPlayback, backgroundPlayback);
                    setState(() {});
                  },
                  title: Text(l10n.setABackgroundPlayback, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setABackgroundPlaybackDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: backgroundPlayback,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    playResume = value ?? !playResume;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.playResume, playResume);
                    setState(() {});
                  },
                  title: Text(l10n.setAAutoResume, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setAAutoResumeDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: playResume,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    autoPlayNext = value ?? !autoPlayNext;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.autoPlayNext, autoPlayNext);
                    setState(() {});
                  },
                  title: Text(l10n.setAAutoPlayNext, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setAAutoPlayNextDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: autoPlayNext,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    playSpeedMemory = value ?? !playSpeedMemory;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.playSpeedMemoryEnabled, playSpeedMemory);
                    setState(() {});
                  },
                  title: Text(l10n.setASpeedMemory, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setASpeedMemoryDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: playSpeedMemory,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    preloadNextEpisode = value ?? !preloadNextEpisode;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.preloadNextEpisode, preloadNextEpisode);
                    setState(() {});
                  },
                  title: Text(l10n.setAPreloadNext, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setAPreloadNextDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: preloadNextEpisode,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    nightEye = value ?? !nightEye;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.nightEyeProtection, nightEye);
                    setState(() {});
                  },
                  title: Text(l10n.setANightEye, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setANightEyeDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: nightEye,
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setAVideoSource, style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    autoSwitchSource = value ?? !autoSwitchSource;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.autoSwitchSource, autoSwitchSource);
                    setState(() {});
                  },
                  title: Text(l10n.setAAutoSwitchSource, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setAAutoSwitchSourceDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: autoSwitchSource,
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setASkipAndPip, style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                // 🆕 自动跳过开关（默认开启）
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    await GStorage.putSetting(
                        SettingsKeys.autoSkipOpEdEnabled, value ?? !autoSkipOpEd);
                    setState(() => autoSkipOpEd = value ?? !autoSkipOpEd);
                  },
                  title: Text(l10n.setAAutoSkipOpEd,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text(
                      l10n.setAAutoSkipOpEdDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: autoSkipOpEd,
                ),
                SettingsTile(
                  onPressed: (_) => _showDefaultSkipDialog(isOp: true),
                  title: Text(l10n.setASkipOpTitle, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setASkipOpDefaultDesc(duration: _formatDuration(skipOpDefault)),
                      style: TextStyle(fontFamily: fontFamily)),
                  value: Text(_formatDuration(skipOpDefault),
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile(
                  onPressed: (_) => _showDefaultSkipDialog(isOp: false),
                  title: Text(l10n.setASkipEdTitle, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setASkipEdDefaultDesc(duration: _formatDuration(skipEdDefault)),
                      style: TextStyle(fontFamily: fontFamily)),
                  value: Text(_formatDuration(skipEdDefault),
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                if (Platform.isAndroid)
                  SettingsTile.switchTile(
                    onToggle: (value) async {
                      androidAutoEnterPIP = value ?? !androidAutoEnterPIP;
                      await GStorage.putSetting<bool>(
                          SettingsKeys.androidAutoEnterPIP,
                          androidAutoEnterPIP);
                      await PipUtils.setAndroidAutoEnterPIPEnabled(
                          androidAutoEnterPIP);
                      setState(() {});
                    },
                    title: Text(l10n.setAAutoPip,
                        style: TextStyle(fontFamily: fontFamily)),
                    description: Text(l10n.setAAutoPipDesc,
                        style: TextStyle(fontFamily: fontFamily)),
                    initialValue: androidAutoEnterPIP,
                  ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    forceAdBlocker = value ?? !forceAdBlocker;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.forceAdBlocker, forceAdBlocker);
                    setState(() {});
                  },
                  title: Text(l10n.setAAdBlock, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setAAdBlockDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: forceAdBlocker,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    playerDisableAnimations = value ?? !playerDisableAnimations;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.playerDisableAnimations,
                        playerDisableAnimations);
                    setState(() {});
                  },
                  title: Text(l10n.setADisableAnim, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setADisableAnimDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: playerDisableAnimations,
                ),
                if (!isDesktop())
                  SettingsTile.switchTile(
                    onToggle: (value) async {
                      brightnessVolumeGesture =
                          value ?? !brightnessVolumeGesture;
                      await GStorage.putSetting<bool>(
                          SettingsKeys.brightnessVolumeGesture,
                          brightnessVolumeGesture);
                      setState(() {});
                    },
                    title:
                        Text(l10n.setAGesture, style: TextStyle(fontFamily: fontFamily)),
                    description: Text(l10n.setAGestureDesc,
                        style: TextStyle(fontFamily: fontFamily)),
                    initialValue: brightnessVolumeGesture,
                  ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    privateMode = value ?? !privateMode;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.privateMode, privateMode);
                    setState(() {});
                  },
                  title: Text(l10n.setAPrivateMode, style: TextStyle(fontFamily: fontFamily)),
                  description:
                      Text(l10n.setAPrivateModeDesc, style: TextStyle(fontFamily: fontFamily)),
                  initialValue: privateMode,
                ),
              ],
            ),
            SettingsSection(
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    showPlayerError = value ?? !showPlayerError;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.showPlayerError, showPlayerError);
                    setState(() {});
                  },
                  title: Text(l10n.setAErrorToast, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setAErrorToastDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: showPlayerError,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    playerDebugMode = value ?? !playerDebugMode;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.playerDebugMode, playerDebugMode);
                    setState(() {});
                  },
                  title: Text(l10n.setADebugMode, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setADebugModeDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: playerDebugMode,
                ),
                SettingsDropdownTile<int>(
                  title: Text(l10n.setALogLevel, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setALogLevelDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  value: playerLogLevel,
                  options: playerLogLevelMap,
                  fallbackLabel: '???',
                  onChanged: updatePlayerLogLevel,
                ),
              ],
            ),
            SettingsSection(
              tiles: [
                SettingsTile(
                  title: Text(l10n.setADefaultSpeed, style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultPlaySpeed,
                    min: 0.25,
                    max: 3,
                    divisions: 11,
                    label: '${defaultPlaySpeed}x',
                    onChanged: (value) {
                      updateDefaultPlaySpeed(
                          double.parse(value.toStringAsFixed(2)));
                    },
                  ),
                ),
                SettingsTile(
                  title: Text(l10n.setADefaultLongPressSpeed,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultShortcutForwardPlaySpeed,
                    min: 1.25,
                    max: 3,
                    divisions: 7,
                    label: '${defaultShortcutForwardPlaySpeed}x',
                    onChanged: (value) {
                      updateDefaultShortcutForwardPlaySpeed(
                          double.parse(value.toStringAsFixed(2)));
                    },
                  ),
                ),
                SettingsTile(
                  description: Slider(
                    value: playerArrowKeySkipTime.toDouble(),
                    min: 0,
                    max: 15,
                    divisions: 15,
                    label: l10n.setASecondsCount(seconds: playerArrowKeySkipTime),
                    onChanged: (value) {
                      final newArrowKeySkipTime = value.toInt();

                      if (value != playerArrowKeySkipTime) {
                        GStorage.putSetting<int>(
                            SettingsKeys.arrowKeySkipTime, newArrowKeySkipTime);
                        setState(() {
                          playerArrowKeySkipTime = newArrowKeySkipTime;
                        });
                      }
                    },
                  ),
                  title: Text(l10n.setAArrowSkipSecs,
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile(
                  onPressed: (_) async {
                    await updateButtonSkipTime();
                  },
                  title: Text(l10n.setASkipTime, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setASkipTimeDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  value: Text(l10n.setASecondsCount(seconds: playerButtonSkipTime),
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile(
                  title: Text(
                      l10n.setAControllerDismissTime(
                          value: formatPlayerControllerLayerDisappearSeconds(
                              playerControllerLayerDisappearSeconds)),
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: playerControllerLayerDisappearSeconds,
                    min: _minPlayerControllerLayerDisappearSeconds,
                    max: _maxPlayerControllerLayerDisappearSeconds,
                    divisions: _playerControllerLayerDisappearDivisions,
                    label: formatPlayerControllerLayerDisappearSeconds(
                        playerControllerLayerDisappearSeconds),
                    onChanged: updatePlayerControllerLayerDisappearSeconds,
                  ),
                ),
                SettingsDropdownTile<PlayerAspectRatio>(
                  title:
                      Text(l10n.setADefaultAspectRatio, style: TextStyle(fontFamily: fontFamily)),
                  value: defaultAspectRatioMode,
                  options: {
                    for (final mode in PlayerAspectRatio.values) mode: mode.label,
                  },
                  onChanged: updateDefaultAspectRatioMode,
                ),
              ],
            ),
            SettingsSection(
              tiles: [
                SettingsTile(
                  onPressed: (_) => resetPlayerSettings(),
                  title:
                      Text(l10n.setAResetDefaults, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setAResetDefaultsDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
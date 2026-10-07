import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/player/danmaku_cache_service.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/settings/settings_list.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/pages/settings/danmaku/danmaku_ch_convert_tile.dart';
import 'package:yhdm/utils/device.dart';

class DanmakuSettingsPage extends StatefulWidget {
  const DanmakuSettingsPage({super.key});

  @override
  State<DanmakuSettingsPage> createState() => _DanmakuSettingsPageState();
}

class _DanmakuSettingsPageState extends State<DanmakuSettingsPage> {
  late final bool compactLayout;
  late double defaultDanmakuArea;
  late double defaultDanmakuOpacity;
  late double defaultDanmakuFontSize;
  late int defaultDanmakuFontWeight;
  late double defaultDanmakuDuration;
  late double defaultDanmakuLineHeight;
  late double defaultdanmakuBorderSize;
  late bool danmakuBorder;
  late bool danmakuTop;
  late bool danmakuBottom;
  late bool danmakuScroll;
  late bool danmakuColor;
  late bool danmakuMassive;
  late bool danmakuDeduplication;
  late bool danmakuDanDanSource;
  late bool danmakuCustom;
  late bool danmakuFollowSpeed;

  @override
  void initState() {
    super.initState();
    compactLayout = isCompact();
    _loadSettingsFromStorage();
  }

  void _loadSettingsFromStorage() {
    final settingContext = SettingContext(compactLayout: compactLayout);
    defaultDanmakuArea = GStorage.getSetting(SettingsKeys.danmakuArea);
    defaultDanmakuOpacity = GStorage.getSetting(SettingsKeys.danmakuOpacity);
    defaultDanmakuFontSize = GStorage.getSetting<double>(
        SettingsKeys.danmakuFontSize,
        context: settingContext);
    defaultDanmakuFontWeight =
        GStorage.getSetting(SettingsKeys.danmakuFontWeight);
    defaultDanmakuDuration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    defaultDanmakuLineHeight =
        GStorage.getSetting(SettingsKeys.danmakuLineHeight);
    danmakuBorder = GStorage.getSetting(SettingsKeys.danmakuBorder);
    defaultdanmakuBorderSize =
        GStorage.getSetting(SettingsKeys.danmakuBorderSize);
    danmakuTop = GStorage.getSetting(SettingsKeys.danmakuTop);
    danmakuBottom = GStorage.getSetting(SettingsKeys.danmakuBottom);
    danmakuScroll = GStorage.getSetting(SettingsKeys.danmakuScroll);
    danmakuColor = GStorage.getSetting(SettingsKeys.danmakuColor);
    danmakuMassive = GStorage.getSetting(SettingsKeys.danmakuMassive);
    danmakuDeduplication =
        GStorage.getSetting<bool>(SettingsKeys.danmakuDeduplication);
    danmakuDanDanSource =
        GStorage.getSetting<bool>(SettingsKeys.danmakuDanDanSource);
    danmakuCustom =
        GStorage.getSetting<bool>(SettingsKeys.customDanmakuEnabled);
    danmakuFollowSpeed =
        GStorage.getSetting<bool>(SettingsKeys.danmakuFollowSpeed);
  }

  Future<void> resetDanmakuSettings() async {
    final l10n = AppLocalizations.of(context)!;
    final bool shouldReset = await KazumiDialog.show<bool>(
          builder: (context) => AlertDialog(
            title: Text(l10n.setBResetDanmakuTitle),
            content: Text(l10n.setBResetDanmakuContent),
            actions: [
              TextButton(
                onPressed: () => KazumiDialog.dismiss(popWith: false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => KazumiDialog.dismiss(popWith: true),
                child: Text(l10n.setBResetDefaults),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldReset) return;

    await GStorage.resetDanmakuSettings();
    if (!mounted) return;
    setState(_loadSettingsFromStorage);
    KazumiDialog.showToast(message: l10n.setBDanmakuResetDone);
  }

  void onBackPressed(BuildContext context) {
    if (KazumiDialog.observer.hasKazumiDialog) {
      KazumiDialog.dismiss();
      return;
    }
  }

  void updateDanmakuArea(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuArea, i);
    setState(() {
      defaultDanmakuArea = i;
    });
  }

  void updateDanmakuOpacity(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuOpacity, i);
    setState(() {
      defaultDanmakuOpacity = i;
    });
  }

  void updateDanmakuFontSize(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuFontSize, i);
    setState(() {
      defaultDanmakuFontSize = i;
    });
  }

  void updateDanmakuDuration(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuDuration, i);
    setState(() {
      defaultDanmakuDuration = i;
    });
  }

  void updateDanmakuLineHeight(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuLineHeight, i);
    setState(() {
      defaultDanmakuLineHeight = i;
    });
  }

  void updateDanmakuFontWeight(int i) async {
    await GStorage.putSetting<int>(SettingsKeys.danmakuFontWeight, i);
    setState(() {
      defaultDanmakuFontWeight = i;
    });
  }

  void updateDanmakuBorderSize(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuBorderSize, i);
    setState(() {
      defaultdanmakuBorderSize = i;
    });
  }

  /// 字节 → 人类可读
  String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: SysAppBar(title: Text(l10n.danmakuSettings)),
        body: SettingsList(
          maxWidth: 1000,
          sections: [
            SettingsSection(
              title: Text(l10n.setBDanmakuSources,
                  style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                // 🔴 合并：弹弹play 一个开关（原 Gamer/BiliBili 重复开关移除），
                // 弹弹/Gamer 来源弹幕统一由它控制；自建弹幕独立开关。
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    danmakuDanDanSource = value ?? !danmakuDanDanSource;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.danmakuDanDanSource, danmakuDanDanSource);
                    setState(() {});
                  },
                  title:
                      Text('弹弹play', style: TextStyle(fontFamily: fontFamily)),
                  initialValue: danmakuDanDanSource,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    danmakuCustom = value ?? !danmakuCustom;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.customDanmakuEnabled, danmakuCustom);
                    setState(() {});
                  },
                  title: Text(l10n.setBCustomDanmaku,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setBCustomDanmakuDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: danmakuCustom,
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setBDanmakuFilter,
                  style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile(
                  onPressed: (_) {
                    context.pushNamed('/settings/danmaku/shield');
                  },
                  title:
                      Text(l10n.setBKeywordFilter, style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setBLocalCache,
                  style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile(
                  onPressed: (_) async {
                    final size = await DanmakuCacheService.totalSize();
                    if (!context.mounted) return;
                    final ok = await KazumiDialog.show<bool>(
                      builder: (ctx) => AlertDialog(
                        title: Text(l10n.setBClearCache),
                        content: Text(
                            l10n.setBClearCacheContent(size: _fmtSize(size))),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(l10n.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(l10n.setBClear),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await DanmakuCacheService.clearAll();
                      if (context.mounted) {
                        KazumiDialog.showToast(message: l10n.setBCacheCleared);
                        setState(() {});
                      }
                    }
                  },
                  title: Text(l10n.setBClearCache,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setBCacheDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  value: FutureBuilder<int>(
                    future: DanmakuCacheService.totalSize(),
                    builder: (ctx, snap) => Text(
                      _fmtSize(snap.data ?? 0),
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setBDanmakuDisplay,
                  style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                const DanmakuChConvertTile(),
                SettingsTile(
                  title: Text(l10n.setBDanmakuArea,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultDanmakuArea,
                    min: 0,
                    max: 1,
                    divisions: 8,
                    label: '${(defaultDanmakuArea * 100).round()}%',
                    onChanged: (value) {
                      updateDanmakuArea(value);
                    },
                  ),
                ),
                SettingsTile(
                  title:
                      Text(l10n.setBDanmakuDuration, style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultDanmakuDuration,
                    min: 2,
                    max: 16,
                    divisions: 14,
                    label: '${defaultDanmakuDuration.round()}',
                    onChanged: (value) {
                      updateDanmakuDuration(value.round().toDouble());
                    },
                  ),
                ),
                SettingsTile(
                  title: Text(l10n.setBDanmakuLineHeight,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultDanmakuLineHeight,
                    min: 0,
                    max: 3,
                    divisions: 30,
                    label: defaultDanmakuLineHeight.toStringAsFixed(1),
                    onChanged: (value) {
                      updateDanmakuLineHeight(
                          double.parse(value.toStringAsFixed(1)));
                    },
                  ),
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    danmakuFollowSpeed = value ?? !danmakuFollowSpeed;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.danmakuFollowSpeed, danmakuFollowSpeed);
                    setState(() {});
                  },
                  title: Text(l10n.setBFollowVideoSpeed,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setBFollowVideoSpeedDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: danmakuFollowSpeed,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    danmakuTop = value ?? !danmakuTop;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.danmakuTop, danmakuTop);
                    setState(() {});
                  },
                  title: Text(l10n.setBTopDanmaku,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: danmakuTop,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    danmakuBottom = value ?? !danmakuBottom;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.danmakuBottom, danmakuBottom);
                    setState(() {});
                  },
                  title: Text(l10n.setBBottomDanmaku,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: danmakuBottom,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    danmakuScroll = value ?? !danmakuScroll;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.danmakuScroll, danmakuScroll);
                    setState(() {});
                  },
                  title: Text(l10n.setBScrollDanmaku,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: danmakuScroll,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    danmakuMassive = value ?? !danmakuMassive;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.danmakuMassive, danmakuMassive);
                    setState(() {});
                  },
                  title: Text(l10n.setBMassiveDanmaku,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setBMassiveDanmakuDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: danmakuMassive,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    danmakuDeduplication = value ?? !danmakuDeduplication;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.danmakuDeduplication,
                        danmakuDeduplication);
                    setState(() {});
                  },
                  title: Text(l10n.setBDanmakuDedup,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setBDanmakuDedupDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: danmakuDeduplication,
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setBDanmakuStyle,
                  style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    danmakuBorder = value ?? !danmakuBorder;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.danmakuBorder, danmakuBorder);
                    setState(() {});
                  },
                  title: Text(l10n.setBDanmakuOutline,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: danmakuBorder,
                ),
                SettingsTile(
                  title:
                      Text(l10n.setBDanmakuOutlineWidth, style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultdanmakuBorderSize,
                    min: 0.1,
                    max: 3,
                    divisions: 29,
                    label: defaultdanmakuBorderSize.toStringAsFixed(1),
                    onChanged: (value) {
                      updateDanmakuBorderSize(
                          double.parse(value.toStringAsFixed(1)));
                    },
                  ),
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    danmakuColor = value ?? !danmakuColor;
                    await GStorage.putSetting<bool>(
                        SettingsKeys.danmakuColor, danmakuColor);
                    setState(() {});
                  },
                  title: Text(l10n.setBDanmakuColor,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: danmakuColor,
                ),
                SettingsTile(
                  title: Text(l10n.setBFontSize,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultDanmakuFontSize,
                    min: 10,
                    max: isCompact() ? 32 : 48,
                    label: '${defaultDanmakuFontSize.floorToDouble()}',
                    onChanged: (value) {
                      updateDanmakuFontSize(value.floorToDouble());
                    },
                  ),
                ),
                SettingsTile(
                  title: Text(l10n.setBFontWeight,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultDanmakuFontWeight.toDouble(),
                    min: 1,
                    max: 9,
                    divisions: 8,
                    label: '$defaultDanmakuFontWeight',
                    onChanged: (value) {
                      updateDanmakuFontWeight(value.toInt());
                    },
                  ),
                ),
                SettingsTile(
                  title:
                      Text(l10n.setBDanmakuOpacity, style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultDanmakuOpacity,
                    min: 0.1,
                    max: 1,
                    label: '${(defaultDanmakuOpacity * 100).round()}%',
                    onChanged: (value) {
                      updateDanmakuOpacity(
                          double.parse(value.toStringAsFixed(2)));
                    },
                  ),
                ),
              ],
            ),
            SettingsSection(
              tiles: [
                SettingsTile(
                  onPressed: (_) => resetDanmakuSettings(),
                  title:
                      Text(l10n.setBRestoreDefaults, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setBRestoreDefaultsDesc,
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

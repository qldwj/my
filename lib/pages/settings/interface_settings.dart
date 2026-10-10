import 'package:card_settings_ui/list/settings_list.dart';
import 'package:card_settings_ui/section/settings_section.dart';
import 'package:card_settings_ui/tile/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/settings/settings_dropdown_tile.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/services/storage/storage.dart';

class InterfaceSettingsPage extends StatefulWidget {
  const InterfaceSettingsPage({super.key});

  @override
  State<InterfaceSettingsPage> createState() => _InterfaceSettingsPageState();
}

class _InterfaceSettingsPageState extends State<InterfaceSettingsPage> {
  late bool showRating;
  late bool showAnimeCounter;
  late bool minorMode;
  late bool liquidGlass;
  late String defaultPage;

  @override
  void initState() {
    super.initState();
    showRating = GStorage.getSetting(SettingsKeys.showRating);
    showAnimeCounter = GStorage.getSetting(SettingsKeys.showAnimeCounter);
    minorMode = GStorage.getSetting(SettingsKeys.minorMode);
    liquidGlass = GStorage.getSetting(SettingsKeys.liquidGlassNav);
    defaultPage = GStorage.getSetting(SettingsKeys.defaultStartupPage);
  }

  void updateDefaultPage(String page) {
    GStorage.putSetting(SettingsKeys.defaultStartupPage, page);
    setState(() {
      defaultPage = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final l10n = AppLocalizations.of(context)!;
    final defaultPageMap = <String, String>{
      '/tab/popular/': l10n.setBPageRecommended,
      '/tab/timeline/': l10n.setBPageTimeline,
      '/tab/collect/': l10n.setBPageFollow,
      '/tab/my/': l10n.setBPageMine,
    };

    return Scaffold(
      appBar: SysAppBar(
        title: Text(l10n.interfaceSettings),
      ),
      body: SettingsList(
        sections: [
          SettingsSection(tiles: [
            SettingsDropdownTile<String>(
              title: Text(l10n.setBStartupPage,
                  style: TextStyle(fontFamily: fontFamily)),
              description: Text(l10n.setBStartupPageDesc,
                  style: TextStyle(fontFamily: fontFamily)),
              value: defaultPage,
              options: defaultPageMap,
              fallbackLabel: l10n.setBPageRecommended,
              onChanged: updateDefaultPage,
            ),
          ]),
          SettingsSection(tiles: [
            SettingsTile.switchTile(
              onToggle: (value) async {
                showRating = value ?? !showRating;
                await GStorage.putSetting(SettingsKeys.showRating, showRating);
                setState(() {});
              },
              title: Text(l10n.setBShowRating,
                      style: TextStyle(fontFamily: fontFamily)),
              description: Text(l10n.setBShowRatingDesc,
                  style: TextStyle(fontFamily: fontFamily)),
              initialValue: showRating,
            ),
          ]),
          SettingsSection(tiles: [
            SettingsTile.switchTile(
              onToggle: (value) async {
                showAnimeCounter = value ?? !showAnimeCounter;
                await GStorage.putSetting(SettingsKeys.showAnimeCounter, showAnimeCounter);
                setState(() {});
              },
              title: Text(l10n.setBShowFollowStats,
                  style: TextStyle(fontFamily: fontFamily)),
              description: Text(l10n.setBShowFollowStatsDesc,
                  style: TextStyle(fontFamily: fontFamily)),
              initialValue: showAnimeCounter,
            ),
          ]),
          SettingsSection(
            title: Text(l10n.setBContentFilter, style: TextStyle(fontFamily: fontFamily)),
            tiles: [              SettingsTile.switchTile(
                onToggle: (value) async {
                  final newValue = value ?? !minorMode;
                  if (!newValue && minorMode) {
                    // 关闭未成年人保护 → 弹出年龄确认
                    final confirmed = await KazumiDialog.show<bool>(
                      builder: (ctx) => AlertDialog(
                        title: Text(l10n.setBAgeConfirmTitle),
                        content: Text(l10n.setBAgeConfirmContent),
                        actions: [
                          TextButton(
                            onPressed: () => KazumiDialog.dismiss(popWith: false),
                            child: Text(l10n.cancel,
                                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                          ),
                          FilledButton(
                            onPressed: () => KazumiDialog.dismiss(popWith: true),
                            child: Text(l10n.setBIAmAdult),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                  }
                  minorMode = newValue;
                  await GStorage.putSetting(SettingsKeys.minorMode, minorMode);
                  setState(() {});
                },
                title: Text(l10n.setBMinorMode,
                    style: TextStyle(fontFamily: fontFamily)),
                description: Text(
                  minorMode ? l10n.setBMinorOn : l10n.setBMinorOff,
                  style: TextStyle(fontFamily: fontFamily)),
                initialValue: minorMode,
              ),
            ],
          ),
          SettingsSection(
            title: Text('底部导航', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.switchTile(
                onToggle: (value) async {
                  liquidGlass = value ?? !liquidGlass;
                  await GStorage.putSetting(SettingsKeys.liquidGlassNav, liquidGlass);
                  setState(() {});
                },
                title: const Text('液态玻璃'),
                description: const Text('底部导航栏使用毛玻璃模糊效果，默认关闭'),
                initialValue: liquidGlass,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

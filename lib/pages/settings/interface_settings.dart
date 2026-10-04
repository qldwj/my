import 'package:card_settings_ui/list/settings_list.dart';
import 'package:card_settings_ui/section/settings_section.dart';
import 'package:card_settings_ui/tile/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/services/storage/storage.dart';

class InterfaceSettingsPage extends StatefulWidget {
  const InterfaceSettingsPage({super.key});

  @override
  State<InterfaceSettingsPage> createState() => _InterfaceSettingsPageState();
}

class _InterfaceSettingsPageState extends State<InterfaceSettingsPage> {
  late bool showRating;
  late bool showAnimeCounter;
  late bool minorMode;
  late String defaultPage;
  final MenuController defaultPageMenuController = MenuController();

  @override
  void initState() {
    super.initState();
    showRating = GStorage.getSetting(SettingsKeys.showRating);
    showAnimeCounter = GStorage.getSetting(SettingsKeys.showAnimeCounter);
    minorMode = GStorage.getSetting(SettingsKeys.minorMode);
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
            SettingsTile.navigation(
              onPressed: (_) async {
                if (defaultPageMenuController.isOpen) {
                  defaultPageMenuController.close();
                } else {
                  defaultPageMenuController.open();
                }
              },
              title: Text(l10n.setBStartupPage,
                  style: TextStyle(fontFamily: fontFamily)),
              description: Text(l10n.setBStartupPageDesc,
                  style: TextStyle(fontFamily: fontFamily)),
              value: MenuAnchor(
                consumeOutsideTap: true,
                controller: defaultPageMenuController,
                builder: (_, __, ___) {
                  return Text(
                    defaultPageMap[defaultPage] ?? l10n.setBPageRecommended,
                    style: TextStyle(fontFamily: fontFamily),
                  );
                },
                menuChildren: [
                  for (final entry in defaultPageMap.entries)
                    MenuItemButton(
                      requestFocusOnHover: false,
                      onPressed: () => updateDefaultPage(entry.key),
                      child: Container(
                        height: 48,
                        constraints: BoxConstraints(minWidth: 112),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              color: entry.key == defaultPage
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                              fontFamily: fontFamily,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
            tiles: [
              SettingsTile.switchTile(
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
        ],
      ),
    );
  }
}

import 'package:card_settings_ui/list/settings_list.dart';
import 'package:card_settings_ui/section/settings_section.dart';
import 'package:card_settings_ui/tile/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
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

  static const Map<String, String> defaultPageMap = {
    '/tab/popular/': '推荐',
    '/tab/timeline/': '时间表',
    '/tab/collect/': '追番',
    '/tab/my/': '我的',
  };

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

    return Scaffold(
      appBar: SysAppBar(
        title: Text('界面设置'),
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
              title: Text('启动界面设置', style: TextStyle(fontFamily: fontFamily)),
              description: Text('设置应用开启时的默认页面',
                  style: TextStyle(fontFamily: fontFamily)),
              value: MenuAnchor(
                consumeOutsideTap: true,
                controller: defaultPageMenuController,
                builder: (_, __, ___) {
                  return Text(
                    defaultPageMap[defaultPage] ?? '推荐',
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
              title: Text('显示评分', style: TextStyle(fontFamily: fontFamily)),
              description: Text('关闭后将在概览中隐藏评分信息',
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
              title: Text('显示追番统计', style: TextStyle(fontFamily: fontFamily)),
              description: Text('启用后将在追番页面下方显示追番统计',
                  style: TextStyle(fontFamily: fontFamily)),
              initialValue: showAnimeCounter,
            ),
          ]),
          SettingsSection(
            title: Text('内容过滤', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.switchTile(
                onToggle: (value) async {
                  final newValue = value ?? !minorMode;
                  if (!newValue && minorMode) {
                    // 关闭未成年人保护 → 弹出年龄确认
                    final confirmed = await KazumiDialog.show<bool>(
                      builder: (ctx) => AlertDialog(
                        title: const Text('⚠️ 年龄确认'),
                        content: const Text(
                          '关闭未成年人保护模式后，您将能看到包含 18+ 内容的番剧。\n\n'
                          '请确认您已年满 18 周岁。\n\n'
                          '本软件仅提供番剧索引和播放功能，所有内容均来自第三方数据源，'
                          '与本软件无关。请用户自行判断并承担相应责任。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => KazumiDialog.dismiss(popWith: false),
                            child: Text('取消',
                                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                          ),
                          FilledButton(
                            onPressed: () => KazumiDialog.dismiss(popWith: true),
                            child: const Text('我已年满 18 周岁'),
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
                title: Text('未成年人保护模式',
                    style: TextStyle(fontFamily: fontFamily)),
                description: Text(
                  minorMode ? '已开启，18+ 内容已隐藏' : '已关闭，将显示 18+ 内容',
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

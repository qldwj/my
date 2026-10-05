import 'dart:io';

import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/pages/my/my_controller.dart';
import 'package:yhdm/request/config/api_endpoints.dart';
import 'package:yhdm/utils/dandan_credentials.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yhdm/utils/device.dart';
import 'package:yhdm/l10n/app_localizations.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    required this.controller,
  });

  final MyController controller;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late dynamic defaultDanmakuArea;
  late dynamic defaultThemeMode;
  late dynamic defaultThemeColor;
  late int exitBehavior = GStorage.getSetting(SettingsKeys.exitBehavior);
  late bool autoUpdate;
  late bool silentDownload;
  late bool checkPluginUpdateOnStartup;
  // 🔥 新增：更新渠道变量
  late String updateChannel;
  double _cacheSizeMB = -1;
  MyController get myController => widget.controller;
  final MenuController menuController = MenuController();

  @override
  void initState() {
    super.initState();
    autoUpdate = GStorage.getSetting(SettingsKeys.autoUpdate);
    silentDownload = GStorage.getSetting(SettingsKeys.silentDownload);
    checkPluginUpdateOnStartup =
        GStorage.getSetting(SettingsKeys.checkPluginUpdateOnStartup);
    
    // 🔥 更新渠道读取：默认 'beta'（预览版），并兼容历史遗留值
    //    'stable' 是用户显式选的「稳定版」→ 保留；
    //    旧值 'preview'、'both'、空 → 统一归一为 'beta'（预览版）并持久化，
    //    避免设置页显示「预览版」但检测逻辑却按「仅正式版」走。
    String rawChannel = GStorage.getSetting(SettingsKeys.updateChannel) ?? 'beta';
    if (rawChannel != 'stable' && rawChannel != 'beta') {
      rawChannel = 'beta';
      GStorage.putSetting(SettingsKeys.updateChannel, 'beta');
    }
    updateChannel = rawChannel;
    
    _getCacheSize();
  }

  void onBackPressed(BuildContext context) {
    if (KazumiDialog.observer.hasKazumiDialog) {
      KazumiDialog.dismiss();
      return;
    }
  }

  Future<Directory> _getCacheDir() async {
    Directory tempDir = await getTemporaryDirectory();
    return Directory('${tempDir.path}/libCachedImageData');
  }

  Future<void> _getCacheSize() async {
    Directory cacheDir = await _getCacheDir();

    if (await cacheDir.exists()) {
      int totalSizeBytes = await _getTotalSizeOfFilesInDir(cacheDir);
      double totalSizeMB = (totalSizeBytes / (1024 * 1024));

      if (mounted) {
        setState(() {
          _cacheSizeMB = totalSizeMB;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _cacheSizeMB = 0.0;
        });
      }
    }
  }

  Future<int> _getTotalSizeOfFilesInDir(final Directory directory) async {
    final List<FileSystemEntity> children = directory.listSync();
    int total = 0;

    try {
      for (final FileSystemEntity child in children) {
        if (child is File) {
          final int length = await child.length();
          total += length;
        } else if (child is Directory) {
          total += await _getTotalSizeOfFilesInDir(child);
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> _clearCache() async {
    final Directory libCacheDir = await _getCacheDir();
    await libCacheDir.delete(recursive: true);
    _getCacheSize();
  }

  void _showCacheDialog() {
    final l10n = AppLocalizations.of(context)!;
    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.setCCacheManagement),
          content: Text(l10n.setCCacheClearConfirm),
          actions: [
            TextButton(
              onPressed: () {
                KazumiDialog.dismiss();
              },
              child: Text(
                l10n.cancel,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () async {
                try {
                  _clearCache();
                } catch (_) {}
                KazumiDialog.dismiss();
              },
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    );
  }

  // 🔥 新增：更新渠道选择对话框
  void _showUpdateChannelDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.setCChooseUpdateChannel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.setCStable),
              leading: Radio<String>(
                value: 'stable',
                groupValue: updateChannel,
                onChanged: (value) {
                  setState(() {
                    updateChannel = value!;
                  });
                  GStorage.putSetting(SettingsKeys.updateChannel, value);
                  Navigator.pop(ctx);
                },
              ),
            ),
            ListTile(
              title: Text(l10n.setCBeta),
              leading: Radio<String>(
                value: 'beta',
                groupValue: updateChannel,
                onChanged: (value) {
                  setState(() {
                    updateChannel = value!;
                  });
                  GStorage.putSetting(SettingsKeys.updateChannel, value);
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.setCClose),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final l10n = AppLocalizations.of(context)!;
    final exitBehaviorTitles = [
      l10n.setCExitKazumi,
      l10n.setCMinimizeToTray,
      l10n.setCAskEveryTime,
    ];
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: SysAppBar(title: Text(l10n.about)),
        body: SettingsList(
          maxWidth: 1000,
          sections: [
            // 特别感谢 Kazumi
            SettingsSection(
              tiles: [
                SettingsTile(
                  title: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: InkWell(
                      onTap: () async {
                        final uri = Uri.parse('https://kazumi.app/');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite_rounded,
                              color: Colors.pink, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            l10n.setCSpecialThanks,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.open_in_new,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              tiles: [
                SettingsTile.navigation(
                  onPressed: (_) {
                    context.pushNamed('/settings/about/license');
                  },
                  title:
                      Text(l10n.setCOpenSourceLicense, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setCOpenSourceLicenseDesc,
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setCExternalLinks, style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.navigation(
                  onPressed: (_) {
                    launchUrl(Uri.parse(ApiEndpoints.projectUrl),
                        mode: LaunchMode.externalApplication);
                  },
                  title: Text(l10n.setCProjectHomepage, style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile.navigation(
                  onPressed: (_) {
                    launchUrl(Uri.parse(ApiEndpoints.sourceUrl),
                        mode: LaunchMode.externalApplication);
                  },
                  title: Text(l10n.setCCodeRepo, style: TextStyle(fontFamily: fontFamily)),
                  value:
                      Text('Github', style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile.navigation(
                  onPressed: (_) {
                    launchUrl(Uri.parse('https://open.juhedenglu.cn/'),
                        mode: LaunchMode.externalApplication);
                  },
                  title: Text(l10n.setCLoginApi, style: TextStyle(fontFamily: fontFamily)),
                  value: Text(l10n.setCAggregatedLogin, style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile.navigation(
                  onPressed: (_) {
                    launchUrl(Uri.parse(ApiEndpoints.iconUrl),
                        mode: LaunchMode.externalApplication);
                  },
                  title: Text(l10n.setCIconArtwork, style: TextStyle(fontFamily: fontFamily)),
                  value:
                      Text('Pixiv', style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile.navigation(
                  onPressed: (_) {
                    launchUrl(Uri.parse(ApiEndpoints.bangumiIndex),
                        mode: LaunchMode.externalApplication);
                  },
                  title: Text(l10n.setCBangumiIndex, style: TextStyle(fontFamily: fontFamily)),
                  value:
                      Text('Bangumi', style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile.navigation(
                  onPressed: (_) {
                    launchUrl(Uri.parse('https://trace.moe'),
                        mode: LaunchMode.externalApplication);
                  },
                  title: Text(l10n.setCReverseSearch, style: TextStyle(fontFamily: fontFamily)),
                  value: Text('trace.moe',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile.navigation(
                  onPressed: (_) {
                    launchUrl(Uri.parse(ApiEndpoints.dandanIndex),
                        mode: LaunchMode.externalApplication);
                  },
                  title: Text(l10n.setCDanmakuSource, style: TextStyle(fontFamily: fontFamily)),
                  description: Text(l10n.setCDanmakuId(id: dandanCredentials['id'] ?? ''),
                      style: TextStyle(fontFamily: fontFamily)),
                  value: Text(l10n.setCDandanOpenPlatform,
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setCCommunity, style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.navigation(
                  onPressed: (_) {
                    launchUrl(Uri.parse(ApiEndpoints.telegramGroup),
                        mode: LaunchMode.externalApplication);
                  },
                  title: Text('Telegram',
                      style: TextStyle(fontFamily: fontFamily)),
                  value: Text(l10n.setCTapToJoin, style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            if (isDesktop()) // 之后如果有非桌面平台的新选项可以移除
              SettingsSection(
                title: Text(l10n.setCDefaultBehavior, style: TextStyle(fontFamily: fontFamily)),
                tiles: [
                  SettingsTile.navigation(
                    onPressed: (_) {
                      if (menuController.isOpen) {
                        menuController.close();
                      } else {
                        menuController.open();
                      }
                    },
                    title:
                        Text(l10n.setCOnClose, style: TextStyle(fontFamily: fontFamily)),
                    value: MenuAnchor(
                      consumeOutsideTap: true,
                      controller: menuController,
                      builder: (_, __, ___) {
                        return Text(exitBehaviorTitles[exitBehavior]);
                      },
                      menuChildren: [
                        for (int i = 0; i < 3; i++)
                          MenuItemButton(
                            requestFocusOnHover: false,
                            onPressed: () {
                              exitBehavior = i;
                              GStorage.putSetting(SettingsKeys.exitBehavior, i);
                              setState(() {});
                            },
                            child: Container(
                              height: 48,
                              constraints: BoxConstraints(minWidth: 112),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  exitBehaviorTitles[i],
                                  style: TextStyle(
                                    color: i == exitBehavior
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            SettingsSection(
              tiles: [
                SettingsTile.navigation(
                  onPressed: (_) {
                    context.pushNamed('/settings/about/logs');
                  },
                  title: Text(l10n.setCErrorLogs, style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setCAppUpdate, style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    autoUpdate = value ?? !autoUpdate;
                    await GStorage.putSetting(
                        SettingsKeys.autoUpdate, autoUpdate);
                    setState(() {});
                  },
                  title: Text(l10n.setCCheckUpdateOnStartup,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: autoUpdate,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    silentDownload = value ?? !silentDownload;
                    await GStorage.putSetting(
                        SettingsKeys.silentDownload, silentDownload);
                    setState(() {});
                  },
                  title: Text(l10n.setCSilentDownload,
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text(
                    l10n.setCSilentDownloadDesc,
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                  initialValue: silentDownload,
                ),
                // 更新渠道行
                SettingsTile.navigation(
                  onPressed: (_) => _showUpdateChannelDialog(),
                  title: Text(l10n.setCUpdateChannel, style: TextStyle(fontFamily: fontFamily)),
                  value: Text(
                    updateChannel == 'beta' ? l10n.setCBeta : l10n.setCStable,
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                ),
                SettingsTile.navigation(
                  onPressed: (_) {
                    myController.checkUpdate();
                  },
                  title:
                      Text(l10n.setCCheckAppUpdate, style: TextStyle(fontFamily: fontFamily)),
                  value: Text(l10n.setCCurrentVersion(version: ApiEndpoints.version),
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setCRuleUpdate, style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    checkPluginUpdateOnStartup =
                        value ?? !checkPluginUpdateOnStartup;
                    await GStorage.putSetting(
                      SettingsKeys.checkPluginUpdateOnStartup,
                      checkPluginUpdateOnStartup,
                    );
                    setState(() {});
                  },
                  title: Text(l10n.setCCheckRuleUpdateOnStartup,
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: checkPluginUpdateOnStartup,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
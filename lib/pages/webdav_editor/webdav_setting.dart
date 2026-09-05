import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/my/sync_log_page.dart';
import 'package:kazumi/pages/my/kazumi_login_page.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/sync/bangumi_sync_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:card_settings_ui/card_settings_ui.dart';

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  State<WebDavSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<WebDavSettingsPage> {
  late bool webDavEnable;
  late bool webDavEnableHistory;
  late bool webDavEnableCollect;
  late bool enableGitProxy;
  late bool enableBangumiProxy;
  late bool bangumiSyncEnable;
  late bool kazumiSyncEnable;
  late bool enableWidget;
  late bool enableNotification;

  @override
  void initState() {
    super.initState();
    webDavEnable = GStorage.getSetting(SettingsKeys.webDavEnable);
    webDavEnableHistory = GStorage.getSetting(SettingsKeys.webDavEnableHistory);
    webDavEnableCollect = GStorage.getSetting(SettingsKeys.webDavEnableCollect);
    enableGitProxy = GStorage.getSetting(SettingsKeys.enableGitProxy);
    enableBangumiProxy = GStorage.getSetting(SettingsKeys.enableBangumiProxy);
    bangumiSyncEnable = GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    kazumiSyncEnable = GStorage.getSetting(SettingsKeys.kazumiSyncEnable);
  }

  void onBackPressed(BuildContext context) {
    if (KazumiDialog.observer.hasKazumiDialog) {
      KazumiDialog.dismiss();
      return;
    }
  }

  Future<void> syncHistoryWithWebDav() async {
    var webDavEnable = GStorage.getSetting(SettingsKeys.webDavEnable);
    if (webDavEnable) {
      KazumiLogger().i('WebDav: manual history sync started');
      KazumiDialog.showToast(message: '正在同步观看记录');
      var webDav = WebDav();
      try {
        if (!webDav.isHistorySyncing) {
          await webDav.ping();
        }
        try {
          await webDav.syncHistory();
          KazumiLogger().i('WebDav: manual history sync completed');
          KazumiDialog.showToast(message: '观看记录同步完成');
        } catch (e) {
          KazumiLogger().w('WebDav: manual history sync failed', error: e);
          KazumiDialog.showToast(message: '观看记录同步失败 ${e.toString()}');
        }
      } catch (e) {
        KazumiLogger().w('WebDav: manual history sync ping failed', error: e);
        KazumiDialog.showToast(message: 'WebDav连接失败');
      }
    } else {
      KazumiDialog.showToast(message: '未开启WebDav同步或配置无效');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: const SysAppBar(title: Text('同步设置')),
        body: SettingsList(
          maxWidth: 1000,
          sections: [
            SettingsSection(
              title: Text('规则仓库', style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    enableGitProxy = value ?? !enableGitProxy;
                    await GStorage.putSetting(
                        SettingsKeys.enableGitProxy, enableGitProxy);
                    setState(() {});
                  },
                  title:
                      Text('规则仓库镜像', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('使用镜像访问规则更新和管理仓库',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: enableGitProxy,
                ),
              ],
            ),
            SettingsSection(
              title: Text('Bangumi', style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    enableBangumiProxy = value ?? !enableBangumiProxy;
                    await GStorage.putSetting(
                        SettingsKeys.enableBangumiProxy, enableBangumiProxy);
                    if (mounted) {
                      setState(() {});
                    }
                  },
                  title: Text('Bangumi 镜像',
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text('使用本地 Bangumi 缓存后端加载热门与分类榜单',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: enableBangumiProxy,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    final tBangumiEnableSync = value ?? !bangumiSyncEnable;
                    final bangumi = BangumiSyncService();
                    if (tBangumiEnableSync == true) {
                      final token =
                          GStorage.getSetting(SettingsKeys.bangumiAccessToken)
                              .trim();
                      if (token.isEmpty) {
                        KazumiDialog.showToast(
                            message: '请先配置 Bangumi 的 Access Token');
                        return;
                      } else {
                        if (!bangumi.initialized) {
                          try {
                            await bangumi.init();
                          } catch (e) {
                            KazumiDialog.showToast(
                                message: "Bangumi 初始化失败，请稍后再试");
                            return;
                          }
                        }
                      }
                    }
                    bangumiSyncEnable = tBangumiEnableSync;
                    await GStorage.putSetting(
                        SettingsKeys.bangumiSyncEnable, bangumiSyncEnable);
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                  },
                  title: Text('Bangumi 同步',
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text('允许与Bangumi自动同步收藏/追番状态',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: bangumiSyncEnable,
                ),
                SettingsTile.navigation(
                  onPressed: (_) async {
                    await context.pushNamed('/settings/bangumi/');
                    bangumiSyncEnable =
                        GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
                    setState(() {});
                  },
                  title: Text('Bangumi 配置',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text('樱花动漫', style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    if (!AuthService.isLoggedIn) {
                      KazumiDialog.showToast(message: '请先登录樱花动漫账号');
                      return;
                    }
                    kazumiSyncEnable = value ?? !kazumiSyncEnable;
                    await GStorage.putSetting(
                        SettingsKeys.kazumiSyncEnable, kazumiSyncEnable);
                    setState(() {});
                  },
                  title: Text('樱花动漫同步',
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text('登录后自动开启，同步收藏到樱花服务器',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: kazumiSyncEnable,
                ),
                SettingsTile.navigation(
                  onPressed: (_) async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const KazumiLoginPage(),
                      ),
                    );
                    if (context.mounted) {
                      setState(() {
                        kazumiSyncEnable = GStorage.getSetting(SettingsKeys.kazumiSyncEnable);
                      });
                    }
                  },
                  title: Text('樱花动漫账号',
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text(AuthService.isLoggedIn ? '已登录' : '未登录',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile(
                  trailing: const Icon(Icons.sync_rounded),
                  onPressed: (_) async {
                    if (!AuthService.isLoggedIn) {
                      KazumiDialog.showToast(message: '请先登录樱花动漫账号');
                      return;
                    }
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const KazumiLoginPage(),
                      ),
                    );
                  },
                  title: Text('立即同步收藏',
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text('进入账号页点击「开始同步」',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile(
                  trailing: const Icon(Icons.bug_report_outlined),
                  onPressed: (_) async {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SyncLogPage()),
                    );
                  },
                  title: Text('同步诊断',
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text('查看详细同步日志和错误信息',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text('WEBDAV', style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    webDavEnable = value ?? !webDavEnable;
                    if (!WebDav().initialized && webDavEnable) {
                      try {
                        await WebDav().init();
                      } catch (e) {
                        webDavEnable = false;
                        KazumiDialog.showToast(message: 'WEBDAV初始化失败 $e');
                      }
                    }
                    if (!webDavEnable) {
                      webDavEnableHistory = false;
                      webDavEnableCollect = false;
                      await GStorage.putSetting(
                          SettingsKeys.webDavEnableHistory, false);
                      await GStorage.putSetting(
                          SettingsKeys.webDavEnableCollect, false);
                    }
                    await GStorage.putSetting(
                        SettingsKeys.webDavEnable, webDavEnable);
                    if (mounted) {
                      setState(() {});
                    }
                  },
                  title: Text('WEBDAV同步',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: webDavEnable,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    if (!webDavEnable) {
                      KazumiDialog.showToast(message: '请先开启WEBDAV同步');
                      return;
                    }
                    webDavEnableHistory = value ?? !webDavEnableHistory;
                    await GStorage.putSetting(
                        SettingsKeys.webDavEnableHistory, webDavEnableHistory);
                    setState(() {});
                  },
                  title:
                      Text('观看记录同步', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('允许自动同步观看记录',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: webDavEnableHistory,
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    if (!webDavEnable) {
                      KazumiDialog.showToast(message: '请先开启WEBDAV同步');
                      return;
                    }
                    webDavEnableCollect = value ?? !webDavEnableCollect;
                    await GStorage.putSetting(
                        SettingsKeys.webDavEnableCollect, webDavEnableCollect);
                    setState(() {});
                  },
                  title: Text('收藏同步', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('允许 WebDAV 参与追番状态同步',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: webDavEnableCollect,
                ),
                SettingsTile.navigation(
                  onPressed: (_) async {
                    context.pushNamed('/settings/webdav/editor');
                  },
                  title: Text('WEBDAV配置',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile(
                  trailing: const Icon(Icons.sync_rounded),
                  onPressed: (_) {
                    syncHistoryWithWebDav();
                  },
                  title: Text('立即同步观看记录',
                      style: TextStyle(fontFamily: fontFamily)),
                  description: Text('与WEBDAV双向合并观看记录',
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

import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/pages/my/bangumi_login_page.dart';

class MyPage extends StatelessWidget {
  const MyPage({super.key});
  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final colorScheme = Theme.of(context).colorScheme;
    final token =
        GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim();
    final isLoggedIn = token.isNotEmpty;

    return Scaffold(
      appBar: const SysAppBar(title: Text('我的'), needTopOffset: false),
      body: SettingsList(
        maxWidth: 1000,
        sections: [
          // ── Bangumi 登录状态条 ──
          if (!isLoggedIn)
            SettingsSection(tiles: [
              SettingsTile(
                onPressed: (_) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BangumiLoginPage(),
                  ),
                ),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_add, color: Colors.blue.shade600),
                ),
                title: Row(
                  children: [
                    Text('当前未登录',
                        style: TextStyle(
                            color: colorScheme.onSurface, fontFamily: fontFamily)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('登录一下吧',
                          style: TextStyle(
                              fontSize: 12, color: Colors.blue.shade600)),
                    ),
                  ],
                ),
                description: Text('登录 Bangumi 后可同步收藏与进度',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
            ])
          else
            SettingsSection(tiles: [
              SettingsTile(
                onPressed: (_) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BangumiLoginPage(),
                  ),
                ),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.check_circle, color: Colors.green.shade600),
                ),
                title: Text('Bangumi 已登录',
                    style: TextStyle(fontFamily: fontFamily, color: Colors.green.shade700)),
                description: Text('点击管理 Bangumi 账号',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
            ]),

          // ── 播放历史与视频源 ──
          SettingsSection(
            title:
                Text('播放历史与视频源', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/history/');
                },
                leading: const Icon(Icons.history_rounded),
                title: Text('历史记录', style: TextStyle(fontFamily: fontFamily)),
                description: Text('查看播放历史记录',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/download/');
                },
                leading: const Icon(Icons.download_rounded),
                title: Text('下载管理', style: TextStyle(fontFamily: fontFamily)),
                description: Text('查看和管理离线下载',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/download-settings');
                },
                leading: const Icon(Icons.settings_rounded),
                title: Text('下载设置', style: TextStyle(fontFamily: fontFamily)),
                description: Text('配置下载并发数等参数',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/plugin/');
                },
                leading: const Icon(Icons.extension),
                title: Text('规则管理', style: TextStyle(fontFamily: fontFamily)),
                description: Text('管理番剧资源规则',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
            ],
          ),
          // ── 播放器设置 ──
          SettingsSection(
            title: Text('播放器设置', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/player');
                },
                leading: const Icon(Icons.display_settings_rounded),
                title: Text('播放设置', style: TextStyle(fontFamily: fontFamily)),
                description: Text('设置播放器相关参数',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/danmaku/');
                },
                leading: const Icon(Icons.subtitles_rounded),
                title: Text('弹幕设置', style: TextStyle(fontFamily: fontFamily)),
                description: Text('设置弹幕相关参数',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/keyboard');
                },
                leading: const Icon(Icons.keyboard_rounded),
                title: Text('操作设置', style: TextStyle(fontFamily: fontFamily)),
                description: Text('设置播放器按键映射',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/proxy');
                },
                leading: const Icon(Icons.vpn_key_rounded),
                title: Text('代理设置', style: TextStyle(fontFamily: fontFamily)),
                description: Text('配置HTTP代理',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
            ],
          ),
          // ── 数据与统计 ──
          SettingsSection(
            title: Text('数据与统计', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/playlist/');
                },
                leading: const Icon(Icons.playlist_play_rounded),
                title: Text('播放列表', style: TextStyle(fontFamily: fontFamily)),
                description: Text('管理你的自定义播放列表',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/stats/');
                },
                leading: const Icon(Icons.bar_chart_rounded),
                title: Text('观看统计', style: TextStyle(fontFamily: fontFamily)),
                description: Text('查看你的追番报告和统计数据',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/webdav/');
                },
                leading: const Icon(Icons.cloud),
                title: Text('同步设置', style: TextStyle(fontFamily: fontFamily)),
                description: Text('设置同步参数',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
            ],
          ),
          // ── 应用与外观 ──
          SettingsSection(
            title: Text('应用与外观', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/theme');
                },
                leading: const Icon(Icons.palette_rounded),
                title: Text('外观设置', style: TextStyle(fontFamily: fontFamily)),
                description: Text('设置应用主题和刷新率',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/interface');
                },
                leading: const Icon(Icons.pages_rounded),
                title: Text('界面设置', style: TextStyle(fontFamily: fontFamily)),
                description: Text('设置应用界面样式',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
            ],
          ),
          // ── 其他 ──
          SettingsSection(
            title: Text('其他', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/about/');
                },
                leading: const Icon(Icons.info_outline_rounded),
                title: Text('关于', style: TextStyle(fontFamily: fontFamily)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

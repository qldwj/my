import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/pages/my/bangumi_login_page.dart';
import 'package:kazumi/pages/my/kazumi_login_page.dart';
import 'package:kazumi/pages/my/task_center_page.dart';
import 'package:kazumi/pages/my/chat_room_page.dart';
import 'package:kazumi/pages/my/feedback_page.dart';
import 'package:kazumi/pages/my/settings_page.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/modules/collect/collect_module.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  int _totalAnime = 0;
  int _totalEpisodes = 0;
  int _collectCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    try {
      final historyRepo = HistoryRepository();
      final histories = historyRepo.getAllHistories();
      
      for (final history in histories) {
        _totalAnime++;
        _totalEpisodes += history.progresses.length;
      }
      
      _collectCount = GStorage.collectibles.length;
    } catch (_) {}
    
    setState(() => _loading = false);
  }

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
          // ═══════════════════════════════════════════
          // 1. 账号管理（Bangumi + 樱花动漫）
          // ═══════════════════════════════════════════
          SettingsSection(
            title: Text('账号管理', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              // ── Bangumi 登录 ──
              if (!isLoggedIn)
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
                )
              else
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

              // ── 樱花动漫账号 ──
              SettingsTile(
                onPressed: (_) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const KazumiLoginPage(),
                  ),
                ),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AuthService.isLoggedIn
                        ? Colors.green.shade50
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    AuthService.isLoggedIn
                        ? Icons.check_circle
                        : Icons.person_add,
                    color: AuthService.isLoggedIn
                        ? Colors.green.shade600
                        : Colors.blue.shade600,
                  ),
                ),
                title: Row(
                  children: [
                    Text(AuthService.isLoggedIn ? '樱花动漫账号已登录' : '樱花动漫账号',
                        style: TextStyle(fontFamily: fontFamily)),
                    if (!AuthService.isLoggedIn) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('验证码登录',
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade600)),
                      ),
                    ],
                  ],
                ),
                description: Text(
                  AuthService.isLoggedIn ? '点击管理账号' : '登录后可同步收藏与进度',
                  style: TextStyle(fontFamily: fontFamily),
                ),
              ),
            ],
          ),

          // ═══════════════════════════════════════════
          // 2. 我的数据（追番报告卡片 + 播放列表 + 同步设置）
          // ═══════════════════════════════════════════
          SettingsSection(
            title: Text('我的数据', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              // ⭐ 追番报告卡片（点击跳转到 StatsPage）
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/stats/');
                },
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.bar_chart_rounded, color: Colors.purple.shade600),
                ),
                title: Row(
                  children: [
                    Text('你的追番报告', style: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    // 显示统计数据
                    if (!_loading) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_totalAnime 部 · $_totalEpisodes 集',
                          style: TextStyle(fontSize: 12, color: Colors.purple.shade600),
                        ),
                      ),
                    ],
                  ],
                ),
                description: Text('查看你的追番报告和统计数据',
                    style: TextStyle(fontFamily: fontFamily)),
              ),

              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/playlist/');
                },
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.playlist_play_rounded, color: Colors.orange.shade600),
                ),
                title: Text('播放列表', style: TextStyle(fontFamily: fontFamily)),
                description: Text('管理你的自定义播放列表',
                    style: TextStyle(fontFamily: fontFamily)),
              ),

              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/webdav/');
                },
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.cloud, color: Colors.teal.shade600),
                ),
                title: Text('同步设置', style: TextStyle(fontFamily: fontFamily)),
                description: Text('设置同步参数',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
            ],
          ),

          // ═══════════════════════════════════════════
          // 3. 历史记录（单独提出）
          // ═══════════════════════════════════════════
          SettingsSection(
            title: Text('历史', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/history/');
                },
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.history_rounded, color: Colors.blue.shade600),
                ),
                title: Text('历史记录', style: TextStyle(fontFamily: fontFamily)),
                description: Text('查看播放历史记录',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
            ],
          ),

          // ═══════════════════════════════════════════
          // 4. 下载管理（单独提出）
          // ═══════════════════════════════════════════
          SettingsSection(
            title: Text('下载', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/download/');
                },
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.download_rounded, color: Colors.green.shade600),
                ),
                title: Text('下载管理', style: TextStyle(fontFamily: fontFamily)),
                description: Text('查看和管理离线下载',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
            ],
          ),

          // ═══════════════════════════════════════════
          // 5. 其他（点击跳转到 SettingsPage）
          // ═══════════════════════════════════════════
          SettingsSection(
            title: Text('其他', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                onPressed: (_) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.more_horiz_rounded, color: Colors.grey.shade700),
                ),
                title: Text('其他设置', style: TextStyle(fontFamily: fontFamily)),
                description: Text('播放设置、规则管理、外观等',
                    style: TextStyle(fontFamily: fontFamily)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
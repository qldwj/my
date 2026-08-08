import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/settings_section_card.dart';
import 'package:kazumi/pages/my/chat_room_page.dart';
import 'package:kazumi/pages/my/feedback_page.dart';
import 'package:kazumi/pages/my/task_center_page.dart';
import 'package:kazumi/pages/settings/proxy/service_status_page.dart';
import 'package:kazumi/services/auth_service.dart';

/// 设置主页（总设置）
///
/// - 不含两个登录（在「我的」页）
/// - 不含历史记录 / 离线下载（在「我的」页）
/// - 仅包含全部设置项：下载与规则 / 播放器 / 数据与统计 / 应用与外观 / 其他
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── 下载与规则 ──
              SettingsSectionCard(
                title: '下载与规则',
                children: [
                  SettingsEntryTile(
                    icon: Icons.settings_rounded,
                    title: '下载设置',
                    description: '配置下载并发数等参数',
                    onTap: () => context.pushNamed('/settings/download-settings'),
                  ),
                  SettingsEntryTile(
                    icon: Icons.extension,
                    title: '规则管理',
                    description: '管理番剧资源规则',
                    onTap: () => context.pushNamed('/settings/plugin/'),
                  ),
                ],
              ),

              // ── 播放器设置 ──
              SettingsSectionCard(
                title: '播放器设置',
                children: [
                  SettingsEntryTile(
                    icon: Icons.display_settings_rounded,
                    title: '播放设置',
                    description: '设置播放器相关参数',
                    onTap: () => context.pushNamed('/settings/player'),
                  ),
                  SettingsEntryTile(
                    icon: Icons.subtitles_rounded,
                    title: '弹幕设置',
                    description: '设置弹幕相关参数',
                    onTap: () => context.pushNamed('/settings/danmaku/'),
                  ),
                  SettingsEntryTile(
                    icon: Icons.keyboard_rounded,
                    title: '操作设置',
                    description: '设置播放器按键映射',
                    onTap: () => context.pushNamed('/settings/keyboard'),
                  ),
                  SettingsEntryTile(
                    icon: Icons.vpn_key_rounded,
                    title: '代理',
                    description: '检测服务连接状态 / 配置HTTP代理',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ServiceStatusPage(),
                      ),
                    ),
                  ),
                ],
              ),

              // ── 数据与统计 ──
              SettingsSectionCard(
                title: '数据与统计',
                children: [
                  SettingsEntryTile(
                    icon: Icons.playlist_play_rounded,
                    title: '播放列表',
                    description: '管理你的自定义播放列表',
                    onTap: () => context.pushNamed('/playlist/'),
                  ),
                  SettingsEntryTile(
                    icon: Icons.bar_chart_rounded,
                    title: '观看统计',
                    description: '查看你的追番报告和统计数据',
                    onTap: () => context.pushNamed('/stats/'),
                  ),
                  SettingsEntryTile(
                    icon: Icons.cloud,
                    title: '同步设置',
                    description: '设置同步参数',
                    onTap: () => context.pushNamed('/settings/webdav/'),
                  ),
                ],
              ),

              // ── 应用与外观 ──
              SettingsSectionCard(
                title: '应用与外观',
                children: [
                  SettingsEntryTile(
                    icon: Icons.palette_rounded,
                    title: '外观设置',
                    description: '设置应用主题和刷新率',
                    onTap: () => context.pushNamed('/settings/theme'),
                  ),
                  SettingsEntryTile(
                    icon: Icons.pages_rounded,
                    title: '界面设置',
                    description: '设置应用界面样式',
                    onTap: () => context.pushNamed('/settings/interface'),
                  ),
                ],
              ),

              // ── 其他 ──
              SettingsSectionCard(
                title: '其他',
                children: [
                  SettingsEntryTile(
                    icon: Icons.emoji_events,
                    title: '任务中心',
                    description: '赚金币、看进度',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TaskCenterPage()),
                    ),
                  ),
                  SettingsEntryTile(
                    icon: Icons.chat,
                    title: '闲聊室',
                    description: AuthService.isLoggedIn ? '已登录' : '登录后可用',
                    onTap: () {
                      if (!AuthService.isLoggedIn) {
                        KazumiDialog.showToast(message: '请先登录樱花动漫账号');
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ChatRoomPage()),
                      );
                    },
                  ),
                  SettingsEntryTile(
                    icon: Icons.feedback_rounded,
                    title: '意见反馈',
                    description: '查看所有反馈及处理情况',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FeedbackPage()),
                    ),
                  ),
                  SettingsEntryTile(
                    icon: Icons.info_outline_rounded,
                    title: '关于',
                    onTap: () => context.pushNamed('/settings/about/'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

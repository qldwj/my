import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/pages/my/task_center_page.dart';
import 'package:kazumi/pages/my/chat_room_page.dart';
import 'package:kazumi/pages/my/feedback_page.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;

    return Scaffold(
      appBar: SysAppBar(
        title: const Text('其他设置'),
        needTopOffset: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SettingsList(
        maxWidth: 1000,
        sections: [
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

          // ── 规则与下载设置 ──
          SettingsSection(
            title: Text('规则与下载设置', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                onPressed: (_) {
                  context.pushNamed('/settings/plugin/');
                },
                leading: const Icon(Icons.extension),
                title: Text('规则管理', style: TextStyle(fontFamily: fontFamily)),
                description: Text('管理番剧资源规则',
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

          // ── 其他功能 ──
          SettingsSection(
            title: Text('其他功能', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                onPressed: (_) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TaskCenterPage()),
                  );
                },
                leading: const Icon(Icons.emoji_events),
                title: Text('任务中心', style: TextStyle(fontFamily: fontFamily)),
                description: Text('赚金币、看进度', style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  if (!AuthService.isLoggedIn) {
                    KazumiDialog.showToast(message: '请先登录樱花动漫账号');
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChatRoomPage()),
                  );
                },
                leading: const Icon(Icons.chat),
                title: Text('闲聊室', style: TextStyle(fontFamily: fontFamily)),
                description: Text(AuthService.isLoggedIn ? '已登录' : '登录后可用', style: TextStyle(fontFamily: fontFamily)),
              ),
              SettingsTile.navigation(
                onPressed: (_) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FeedbackPage()),
                  );
                },
                leading: const Icon(Icons.feedback_rounded),
                title: Text('意见反馈', style: TextStyle(fontFamily: fontFamily)),
                description: Text('查看所有反馈及处理情况', style: TextStyle(fontFamily: fontFamily)),
              ),
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
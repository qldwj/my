import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/settings_section_card.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 聊天设置页
///
/// - 全局消息提醒：在首页/追番/收藏/详情等页面顶部弹出好友消息横幅
/// - 播放视频时永不弹横幅（避免打扰观看）
class ChatSettingsPage extends StatefulWidget {
  const ChatSettingsPage({super.key});

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  bool _bannerEnabled = true;
  bool _hideOnline = false;

  @override
  void initState() {
    super.initState();
    _bannerEnabled = GStorage.getSetting(SettingsKeys.chatGlobalBanner);
    _hideOnline = SocialService.restoreLocalProfile()?.hideOnline ?? false;
  }

  Future<void> _toggleHideOnline(bool value) async {
    setState(() => _hideOnline = value);
    final error = await SocialService.updateProfile(hideOnline: value);
    if (!mounted) return;
    if (error != null) {
      setState(() => _hideOnline = !value);
      KazumiDialog.showToast(message: '❌ $error');
    } else {
      KazumiDialog.showToast(
          message: value ? '已隐藏在线状态' : '已恢复显示在线状态');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('聊天设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsSectionCard(
            title: '全局消息提醒',
            children: [
              SwitchListTile(
                title: const Text('开启消息横幅'),
                subtitle: const Text('收到好友消息时，在页面顶部弹出横幅（头像+昵称+内容），点击直达聊天'),
                value: _bannerEnabled,
                onChanged: (value) async {
                  setState(() => _bannerEnabled = value);
                  await GStorage.putSetting(SettingsKeys.chatGlobalBanner, value);
                },
              ),
            ],
          ),
          SettingsSectionCard(
            title: '隐私',
            children: [
              SwitchListTile(
                title: const Text('隐藏我的在线状态'),
                subtitle: const Text('开启后好友看不到你是否在线'),
                value: _hideOnline,
                onChanged: _toggleHideOnline,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '● 在首页、追番、收藏、详情等页面浏览时会弹出好友消息横幅\n'
              '● 播放视频时不会弹出，避免打扰观看\n'
              '● 横幅 6 秒后自动消失，可手动关闭\n'
              '● 消息页内的系统通知不受此开关影响',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

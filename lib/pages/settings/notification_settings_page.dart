import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/settings_section_card.dart';
import 'package:kazumi/services/notification/anime_update_notification_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/date_time.dart';

/// 追番更新提醒设置页
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _enabled = false;
  int _intervalHours = 12;
  bool _onlyWatching = true;
  bool _sequelNotify = true;
  int _lastCheck = 0;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _enabled = GStorage.getSetting(SettingsKeys.animeUpdateNotify);
    _intervalHours =
        GStorage.getSetting(SettingsKeys.animeUpdateCheckIntervalHours);
    _onlyWatching = GStorage.getSetting(SettingsKeys.animeUpdateOnlyWatching);
    _sequelNotify = GStorage.getSetting(SettingsKeys.sequelNotify);
    _lastCheck = GStorage.getSetting(SettingsKeys.animeUpdateLastCheck);
  }

  Future<void> _toggleEnabled(bool value) async {
    setState(() => _enabled = value);
    await GStorage.putSetting(SettingsKeys.animeUpdateNotify, value);
    if (value) {
      // 开启后立即检查一次
      await AnimeUpdateNotificationService.checkForUpdates(manual: true);
      if (mounted) {
        setState(() {
          _lastCheck = GStorage.getSetting(SettingsKeys.animeUpdateLastCheck);
        });
      }
    }
  }

  Future<void> _setInterval(int hours) async {
    setState(() => _intervalHours = hours);
    await GStorage.putSetting(SettingsKeys.animeUpdateCheckIntervalHours, hours);
  }

  Future<void> _toggleOnlyWatching(bool value) async {
    setState(() => _onlyWatching = value);
    await GStorage.putSetting(SettingsKeys.animeUpdateOnlyWatching, value);
  }

  Future<void> _toggleSequelNotify(bool value) async {
    setState(() => _sequelNotify = value);
    await GStorage.putSetting(SettingsKeys.sequelNotify, value);
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    await AnimeUpdateNotificationService.checkForUpdates(manual: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _lastCheck = GStorage.getSetting(SettingsKeys.animeUpdateLastCheck);
    });
    KazumiDialog.showToast(message: '检查完成，有新番会推送通知');
  }

  /// 🆕 立即发送一条测试通知（验证通知通道）
  Future<void> _sendTestNotification() async {
    if (_checking) return;
    setState(() => _checking = true);
    await AnimeUpdateNotificationService.sendTestNotification();
    if (!mounted) return;
    setState(() => _checking = false);
    KazumiDialog.showToast(message: '已发送测试通知，请看通知栏');
  }

  String _formatLastCheck(int ts) {
    if (ts <= 0) return '尚未检查';
    return '上次检查：${dateFormat(ts)}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(title: const Text('追番提醒')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsSectionCard(
                title: '追番更新提醒',
                children: [
                  SwitchListTile(
                    title: const Text('开启追番提醒'),
                    subtitle: const Text('收藏的番剧有新集未看时推送通知'),
                    value: _enabled,
                    onChanged: _toggleEnabled,
                  ),
                  if (_enabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('检查间隔'),
                      trailing: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 8, label: Text('8小时')),
                          ButtonSegment(value: 12, label: Text('12小时')),
                          ButtonSegment(value: 24, label: Text('24小时')),
                        ],
                        selected: {_intervalHours},
                        onSelectionChanged: (s) => _setInterval(s.first),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('仅提醒"在看"'),
                      subtitle: const Text('关闭后"想看"的番剧也会提醒'),
                      value: _onlyWatching,
                      onChanged: _toggleOnlyWatching,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('续作开播提醒'),
                      subtitle: const Text('收藏番剧的续作 45 天内开播时通知'),
                      value: _sequelNotify,
                      onChanged: _toggleSequelNotify,
                    ),
                  ],
                ],
              ),
              SettingsSectionCard(
                title: '手动操作',
                children: [
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('立即检查一次'),
                    subtitle: Text(_formatLastCheck(_lastCheck)),
                    trailing: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: _checking ? null : _checkNow,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notifications_rounded),
                    title: const Text('发送测试通知'),
                    subtitle: const Text('立即弹出一条通知，验证通知通道是否正常'),
                    trailing: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: _checking ? null : _sendTestNotification,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '检查原理：通过 Bangumi 数据对比"已放送集数"与"本地已看集数"，'
                  '有未看新集才会推送（完结超过 30 天的老番不会打扰你）。\n\n'
                  '说明：目前仅在 App 运行期间自动检查（每小时触发一次，按间隔执行）；'
                  '如需手机熄屏/App 被清理后也能提醒，可后续接入系统级后台任务（workmanager）。',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

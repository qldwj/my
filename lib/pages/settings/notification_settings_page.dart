import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/settings_section_card.dart';
import 'package:kazumi/l10n/app_localizations.dart';
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
  bool _badgeNotify = true;
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
    _badgeNotify = GStorage.getSetting(SettingsKeys.notificationBadge);
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

  Future<void> _toggleBadgeNotify(bool value) async {
    setState(() => _badgeNotify = value);
    await GStorage.putSetting(SettingsKeys.notificationBadge, value);
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
    KazumiDialog.showToast(message: AppLocalizations.of(context)!.setACheckDone);
  }

  /// 🆕 立即发送一条测试通知（验证通知通道）
  Future<void> _sendTestNotification() async {
    if (_checking) return;
    setState(() => _checking = true);
    await AnimeUpdateNotificationService.sendTestNotification();
    if (!mounted) return;
    setState(() => _checking = false);
    KazumiDialog.showToast(message: AppLocalizations.of(context)!.setATestNotifSent);
  }

  String _formatLastCheck(int ts) {
    final l10n = AppLocalizations.of(context)!;
    if (ts <= 0) return l10n.setANeverChecked;
    return l10n.setALastCheck(time: dateFormat(ts));
  }

  /// 🆕 显示已屏蔽更新提醒的番剧列表，可取消屏蔽
  void _showMutedList() {
    final l10n = AppLocalizations.of(context)!;
    final muted = GStorage.notifyMuted.toMap();
    if (muted.isEmpty) {
      KazumiDialog.showToast(message: l10n.setANoMuted);
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final sheetL10n = AppLocalizations.of(ctx)!;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(sheetL10n.setAMutedListTitle(count: muted.length),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Divider(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView(
                  shrinkWrap: true,
                  children: muted.entries.map((e) {
                    return ListTile(
                      leading: const Icon(Icons.notifications_off_outlined,
                        color: Colors.grey),
                      title: Text(e.value, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(sheetL10n.setAMutedSubtitle, style: const TextStyle(fontSize: 12)),
                      trailing: TextButton(
                        onPressed: () {
                          GStorage.notifyMuted.delete(e.key);
                          GStorage.notifyMuted.flush();
                          setState(() {});
                          Navigator.pop(ctx);
                          KazumiDialog.showToast(message: sheetL10n.setAUnmutedDone(name: e.value));
                        },
                        child: Text(sheetL10n.setAUnmute, style: const TextStyle(fontSize: 12)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SysAppBar(title: Text(l10n.followNotify)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsSectionCard(
                title: l10n.setANotifSectionTitle,
                children: [
                  SwitchListTile(
                    title: Text(l10n.setAEnableFollowNotify),
                    subtitle: Text(l10n.setAEnableFollowNotifyDesc),
                    value: _enabled,
                    onChanged: _toggleEnabled,
                  ),
                  if (_enabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: Text(l10n.setACheckInterval),
                      trailing: SegmentedButton<int>(
                        segments: [
                          ButtonSegment(value: 8, label: Text(l10n.setAHours(hours: 8))),
                          ButtonSegment(value: 12, label: Text(l10n.setAHours(hours: 12))),
                          ButtonSegment(value: 24, label: Text(l10n.setAHours(hours: 24))),
                        ],
                        selected: {_intervalHours},
                        onSelectionChanged: (s) => _setInterval(s.first),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: Text(l10n.setAOnlyWatching),
                      subtitle: Text(l10n.setAOnlyWatchingDesc),
                      value: _onlyWatching,
                      onChanged: _toggleOnlyWatching,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: Text(l10n.setASequelNotify),
                      subtitle: Text(l10n.setASequelNotifyDesc),
                      value: _sequelNotify,
                      onChanged: _toggleSequelNotify,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: Text(l10n.setABadge),
                      subtitle: Text(l10n.setABadgeDesc),
                      value: _badgeNotify,
                      onChanged: _toggleBadgeNotify,
                    ),
                  ],
                ],
              ),
              SettingsSectionCard(
                title: l10n.setAManualOps,
                children: [
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: Text(l10n.setACheckNow),
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
                    title: Text(l10n.setASendTest),
                    subtitle: Text(l10n.setASendTestDesc),
                    trailing: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: _checking ? null : _sendTestNotification,
                  ),
                  // 🆕 已屏蔽的番剧
                  if (_enabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.notifications_off_outlined),
                      title: Text(l10n.setAMutedTitle),
                      subtitle: Text(
                        GStorage.notifyMuted.isEmpty
                            ? l10n.setAMutedEmpty
                            : l10n.setAMutedCount(count: GStorage.notifyMuted.length),
                      ),
                      onTap: _showMutedList,
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.setANotifFootnote,
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

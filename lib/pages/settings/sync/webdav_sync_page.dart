import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:yhdm/bean/settings/settings_detail_scaffold.dart';
import 'package:yhdm/bean/settings/settings_list.dart';
import 'package:yhdm/bean/widget/state_presentation.dart';
import 'package:yhdm/pages/settings/sync/sync_settings_widgets.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/sync/webdav.dart';
import 'package:yhdm/services/sync/danmaku_shield_sync_service.dart';

class WebDavSyncPage extends StatefulWidget {
  const WebDavSyncPage({super.key, required this.danmakuShieldSync});

  final DanmakuShieldSyncService danmakuShieldSync;

  @override
  State<WebDavSyncPage> createState() => _WebDavSyncPageState();
}

class _WebDavSyncPageState extends State<WebDavSyncPage> {
  bool _busy = false;
  bool _failed = false;
  String? _message;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _failed = false;
      _message = l10n.setBConnectingWebdav;
    });
    try {
      await action();
    } catch (e) {
      KazumiLogger().w('WebDAV settings operation failed', error: e);
      if (mounted) {
        _failed = true;
        _message = l10n.setBSyncFailedGeneric;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setEnabled(bool enabled) => _run(() async {
        await WebDav().setEnabled(enabled);
        _message = null;
      });

  Future<void> _syncHistory() async {
    final l10n = AppLocalizations.of(context)!;
    await _run(() async {
      final webDav = WebDav();
      if (!webDav.initialized) {
        await webDav.init();
      } else if (!webDav.isHistorySyncing) {
        await webDav.ping();
      }
      if (mounted) setState(() => _message = l10n.setBSyncingHistory);
      await webDav.syncHistory();
      _message = l10n.setBHistorySynced;
    });
  }

  Future<void> _configure() async {
    await context.pushNamed('/settings/webdav/editor');
    if (mounted) {
      setState(() {
        _message = null;
        _failed = false;
      });
    }
  }

  Future<void> _syncDanmakuShield() async {
    final l10n = AppLocalizations.of(context)!;
    await _run(() async {
      if (mounted) setState(() => _message = l10n.setBSyncingKeywords);
      await widget.danmakuShieldSync.sync();
      _message = l10n.setBKeywordsSynced;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = GStorage.getSetting(SettingsKeys.webDavEnable);
    final history = GStorage.getSetting(SettingsKeys.webDavEnableHistory);
    final collect = GStorage.getSetting(SettingsKeys.webDavEnableCollect);
    final shield = GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield);
    final url = GStorage.getSetting(SettingsKeys.webDavURL).trim();
    final configured = url.isNotEmpty;
    final host = Uri.tryParse(url)?.host;
    return PopScope(
      canPop: !_busy,
      child: SettingsDetailScaffold(
        title: Text(l10n.setBMultiDeviceSync),
        body: SyncPageBody(
          maxWidth: 720,
          children: [
            SyncPageIntro(
              icon: Icons.devices_rounded,
              title: 'WebDAV',
              description: l10n.setBWebdavIntro,
            ),
            SettingsSection(
              margin: EdgeInsets.zero,
              tiles: [
                SettingsTile(
                  leading: Icons.dns_rounded,
                  title: Text(configured ? l10n.setBSyncServer : l10n.setBConnectCloud),
                  description: Text(configured
                      ? (host == null || host.isEmpty ? l10n.setBServerSaved : host)
                      : l10n.setBNeedsWebdav),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  enabled: !_busy,
                  onPressed: (_) => _configure(),
                ),
                SettingsTile.switchTile(
                  leading: Icons.cloud_sync_rounded,
                  title: Text(l10n.setBEnableWebdav),
                  description: Text(configured
                      ? (enabled ? l10n.setBEnabledChoose : l10n.setBEnableThenChoose)
                      : l10n.setBConfigureServerFirst),
                  initialValue: enabled,
                  enabled: configured && !_busy,
                  onToggle: (value) => _setEnabled(value ?? !enabled),
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.setBSyncedContent),
              margin: EdgeInsets.zero,
              tiles: [
                SettingsTile.switchTile(
                  leading: Icons.history_rounded,
                  title: Text(l10n.setBWatchHistory),
                  description: Text(l10n.setBHistoryAutoDesc),
                  initialValue: history,
                  enabled: enabled && !_busy,
                  onToggle: (value) async {
                    await GStorage.putSetting(
                        SettingsKeys.webDavEnableHistory, value ?? !history);
                    if (mounted) setState(() {});
                  },
                ),
                SettingsTile.switchTile(
                  leading: Icons.favorite_rounded,
                  title: Text(l10n.setBFavorites),
                  description: Text(l10n.setBFavoritesAutoDesc),
                  initialValue: collect,
                  enabled: enabled && !_busy,
                  onToggle: (value) async {
                    await GStorage.putSetting(
                        SettingsKeys.webDavEnableCollect, value ?? !collect);
                    if (mounted) setState(() {});
                  },
                ),
                SettingsTile.switchTile(
                  leading: Icons.filter_alt_rounded,
                  title: Text(l10n.setBDanmakuKeywords),
                  description: Text(l10n.setBKeywordsAutoDesc),
                  initialValue: shield,
                  enabled: enabled && !_busy,
                  onToggle: (value) async {
                    final syncEnabled = value ?? !shield;
                    await GStorage.putSetting(
                        SettingsKeys.webDavEnableDanmakuShield, syncEnabled);
                    if (!mounted) return;
                    setState(() {});
                    if (syncEnabled) await _syncDanmakuShield();
                  },
                ),
              ],
            ),
            StateActionButton(
              onPressed: enabled && !_busy ? _syncHistory : null,
              text: _busy ? l10n.setBPleaseWait : l10n.setBSyncHistoryNow,
              icon: Icons.sync_rounded,
            ),
            StateActionButton.tonal(
              onPressed:
                  enabled && shield && !_busy ? _syncDanmakuShield : null,
              text: l10n.setBSyncKeywordsNow,
              icon: Icons.sync_rounded,
            ),
            if (_message != null)
              SyncFeedback(message: _message!, error: _failed, busy: _busy),
          ],
        ),
      ),
    );
  }
}

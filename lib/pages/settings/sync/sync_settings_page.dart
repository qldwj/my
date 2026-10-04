import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/repositories/danmaku_shield_repository.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:kazumi/services/storage/storage.dart';

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  bool get _bangumiHasToken =>
      GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;
  bool get _bangumiEnabled =>
      GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
  bool get _webdavHasConfig =>
      GStorage.getSetting(SettingsKeys.webDavURL).trim().isNotEmpty;
  bool get _webdavEnabled => GStorage.getSetting(SettingsKeys.webDavEnable);

  // ── 单向同步 ──
  bool _oneWayExpanded = false;
  bool _busy = false;

  // 4 个可开关的单项（默认全部参与）
  bool _incHistory = true;
  bool _incCollect = true;
  bool _incDanmaku = true;
  bool _incGoal = true;

  @override
  void initState() {
    super.initState();
    _incGoal = GStorage.getSetting(SettingsKeys.oneWaySyncGoal);
    _incDanmaku = GStorage.getSetting(SettingsKeys.oneWaySyncDanmaku);
    _incHistory = GStorage.getSetting(SettingsKeys.oneWaySyncHistory);
    _incCollect = GStorage.getSetting(SettingsKeys.oneWaySyncCollect);
  }

  /// 一键同步：upload=true 本机→云端（覆盖云端）；false 云端→本机（覆盖本机）
  Future<void> _oneWaySync({required bool upload}) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    if (!_webdavHasConfig) {
      KazumiDialog.showToast(message: l10n.setBConfigureWebdavFirst);
      return;
    }
    final dirLabel = upload ? l10n.setBUpload : l10n.setBDownload;
    // 🛡️ 「下载=云端覆盖本机」前先快照，避免误点导致收藏丢失
    if (!upload) {
      await GStorage.snapshotBeforeOverwrite();
    }
    setState(() => _busy = true);
    final done = <String>[];
    final failed = <String>[];
    try {
      final webDav = WebDav();
      await webDav.init();

      if (_incHistory) {
        try {
          if (upload) {
            await webDav.uploadHistory();
          } else {
            await webDav.downloadHistory();
          }
          done.add(l10n.setBHistoryItem);
        } catch (_) {
          failed.add(l10n.setBHistoryItem);
        }
      }
      if (_incCollect) {
        try {
          if (upload) {
            await webDav.uploadCollectibles();
          } else {
            await webDav.downloadCollectibles();
          }
          done.add(l10n.setBFavorites);
        } catch (_) {
          failed.add(l10n.setBFavorites);
        }
      }
      if (_incDanmaku) {
        try {
          final repo = inject<IDanmakuShieldRepository>();
          if (upload) {
            final deviceId = await repo.getDeviceId();
            final state = await repo.buildLocalState();
            await webDav.uploadDanmakuShieldState(deviceId, state.encode());
          } else {
            final remote = await webDav.downloadDanmakuShieldState();
            if (remote == null) {
              throw Exception('云端暂无弹幕规则');
            }
            await repo.mergeSyncState(remote);
          }
          done.add(l10n.setBDanmakuRules);
        } catch (_) {
          failed.add(l10n.setBDanmakuRules);
        }
      }
      if (_incGoal) {
        try {
          // 追番目标（每周目标）走 WebDAV
          if (upload) {
            await webDav.uploadSettings();
          } else {
            await webDav.downloadSettings();
          }
          done.add(l10n.setBWeeklyGoal);
        } catch (_) {
          failed.add(l10n.setBWeeklyGoal);
        }
      }
      // 下载完成后刷新本地列表
      if (!upload && mounted) {
        try {
          inject<CollectController>().loadCollectibles();
        } catch (_) {}
      }
    } catch (e) {
      failed.add(l10n.setBInitFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) {
      final msg = StringBuffer();
      if (done.isNotEmpty) {
        msg.write(l10n.setBSyncDone(dir: dirLabel, items: done.join('、')));
      }
      if (failed.isNotEmpty) {
        if (msg.isNotEmpty) msg.write('\n');
        msg.write(l10n.setBSyncFailed(items: failed.join('、')));
      }
      if (msg.isEmpty) msg.write(l10n.setBSyncNothingSelected);
      KazumiDialog.showToast(message: msg.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text(l10n.syncSettings,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        needTopOffset: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.setBChooseServices,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(l10n.setBMultiServicesHint,
                      style: text.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 16),

                  _SyncServiceTile(
                    icon: Icons.brightness_6_rounded,
                    title: l10n.setBBangumiSyncTitle,
                    subtitle: l10n.setBBangumiSyncSub,
                    status: _bangumiHasToken
                        ? (_bangumiEnabled ? l10n.setBSyncOn : l10n.setBSyncConfigured)
                        : l10n.setBSyncNotConfigured,
                    statusColor:
                        _bangumiHasToken ? Colors.green : colors.outline,
                    iconBg: colors.primaryContainer,
                    iconFg: colors.onPrimaryContainer,
                    onTap: () async {
                      await context.pushNamed('/settings/sync/bangumi');
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),

                  _SyncServiceTile(
                    icon: Icons.cloud_sync_rounded,
                    title: l10n.setBWebdavSyncTitle,
                    subtitle: l10n.setBWebdavSyncSub,
                    status: _webdavHasConfig
                        ? (_webdavEnabled ? l10n.setBSyncOn : l10n.setBSyncConfigured)
                        : l10n.setBSyncNotConfigured,
                    statusColor:
                        _webdavHasConfig ? Colors.green : colors.outline,
                    iconBg: colors.tertiaryContainer,
                    iconFg: colors.onTertiaryContainer,
                    onTap: () async {
                      await context.pushNamed('/settings/webdav/');
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(height: 24),

                  // ══════════ 单向同步 ══════════
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(28),
                    child: Column(
                      children: [
                        // 标题行：一键同步按钮 + 右侧展开箭头
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(Icons.swap_vert_rounded,
                                    color: colors.primary, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l10n.setBOneWaySync,
                                        style: text.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(l10n.setBOneWaySyncDesc,
                                        style: text.bodySmall?.copyWith(
                                            color: colors.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              // 展开箭头
                              IconButton(
                                icon: Icon(
                                  _oneWayExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: colors.onSurfaceVariant,
                                ),
                                onPressed: () => setState(
                                    () => _oneWayExpanded = !_oneWayExpanded),
                              ),
                            ],
                          ),
                        ),
                        // 上传 / 下载 单独一行（原来挤在标题行里把文字压成竖排）
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Row(
                            children: [
                              // 上传 / 下载 两个按钮
                              FilledButton.tonalIcon(
                                onPressed: _busy
                                    ? null
                                    : () => _oneWaySync(upload: true),
                                icon: const Icon(Icons.upload_rounded, size: 16),
                                label: Text(l10n.setBUpload),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonalIcon(
                                onPressed: _busy
                                    ? null
                                    : () => _oneWaySync(upload: false),
                                icon: const Icon(Icons.download_rounded, size: 16),
                                label: Text(l10n.setBDownload),
                              ),
                            ],
                          ),
                        ),
                        // 展开区：4 个开关
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: Column(
                              children: [
                                if (GStorage.hasSnapshot)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.restore_rounded, size: 18),
                                    title: Text(
                                      l10n.setBRestoreSnapshot(count: GStorage.snapshotCollectCount),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    onTap: () async {
                                      final n = await GStorage
                                          .restoreCollectiblesFromSnapshot();
                                      if (!mounted) return;
                                      KazumiDialog.showToast(
                                          message: l10n.setBRestoredFavorites(n: n));
                                      setState(() {});
                                    },
                                  ),
                                const Divider(height: 1),
                                _switchTile(
                                  title: l10n.setBWatchHistory,
                                  subtitle: l10n.setBWatchHistorySub,
                                  value: _incHistory,
                                  onChanged: (v) {
                                    setState(() => _incHistory = v);
                                    GStorage.putSetting(
                                        SettingsKeys.oneWaySyncHistory, v);
                                  },
                                ),
                                _switchTile(
                                  title: l10n.setBFavorites,
                                  subtitle: l10n.setBFavoritesSub,
                                  value: _incCollect,
                                  onChanged: (v) {
                                    setState(() => _incCollect = v);
                                    GStorage.putSetting(
                                        SettingsKeys.oneWaySyncCollect, v);
                                  },
                                ),
                                _switchTile(
                                  title: l10n.setBDanmakuRules,
                                  subtitle: l10n.setBDanmakuKeywords,
                                  value: _incDanmaku,
                                  onChanged: (v) {
                                    setState(() => _incDanmaku = v);
                                    GStorage.putSetting(
                                        SettingsKeys.oneWaySyncDanmaku, v);
                                  },
                                ),
                                _switchTile(
                                  title: l10n.setBWeeklyGoal,
                                  subtitle: l10n.setBWeeklyGoalSub,
                                  value: _incGoal,
                                  onChanged: (v) {
                                    setState(() => _incGoal = v);
                                    GStorage.putSetting(
                                        SettingsKeys.oneWaySyncGoal, v);
                                  },
                                ),
                              ],
                            ),
                          ),
                          crossFadeState: _oneWayExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 200),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SyncServiceTile extends StatelessWidget {
  const _SyncServiceTile({
    required this.icon, required this.title, required this.subtitle,
    required this.status, required this.statusColor,
    required this.iconBg, required this.iconFg, required this.onTap,
  });

  final IconData icon;
  final String title, subtitle, status;
  final Color statusColor, iconBg, iconFg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: iconFg, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.circle, size: 8, color: statusColor),
                      const SizedBox(width: 4),
                      Text(status, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
                    ]),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }
}

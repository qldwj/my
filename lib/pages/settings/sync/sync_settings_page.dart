import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/my/kazumi_login_page.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/repositories/danmaku_shield_repository.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/sync/kazumi_sync_service.dart';
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
    if (!_webdavHasConfig) {
      KazumiDialog.showToast(message: '请先配置 WebDAV');
      return;
    }
    final dirLabel = upload ? '上传' : '下载';
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
          done.add('历史');
        } catch (_) {
          failed.add('历史');
        }
      }
      if (_incCollect) {
        try {
          if (upload) {
            await webDav.uploadCollectibles();
          } else {
            await webDav.downloadCollectibles();
          }
          done.add('收藏');
        } catch (_) {
          failed.add('收藏');
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
          done.add('弹幕规则');
        } catch (_) {
          failed.add('弹幕规则');
        }
      }
      if (_incGoal) {
        try {
          // 追番目标走樱花云（上传 / 下载）
          if (upload) {
            await KazumiSyncService.syncSettings();
          } else {
            await KazumiSyncService.downloadSettings();
          }
          done.add('追番目标');
        } catch (_) {
          failed.add('追番目标');
        }
      }
      // 下载完成后刷新本地列表
      if (!upload && mounted) {
        try {
          inject<CollectController>().loadCollectibles();
        } catch (_) {}
      }
    } catch (e) {
      failed.add('初始化失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) {
      final msg = StringBuffer();
      if (done.isNotEmpty) msg.write('✅ 已$dirLabel：${done.join('、')}');
      if (failed.isNotEmpty) {
        if (msg.isNotEmpty) msg.write('\n');
        msg.write('❌ 失败：${failed.join('、')}');
      }
      if (msg.isEmpty) msg.write('未选择任何同步项');
      KazumiDialog.showToast(message: msg.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text('同步设置',
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
                  Text('选择需要的服务',
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('也可以同时使用多个服务来同步数据',
                      style: text.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 16),

                  _SyncServiceTile(
                    icon: Icons.brightness_6_rounded,
                    title: 'Bangumi 追番同步',
                    subtitle: '与Bangumi保持相同的追番状态',
                    status: _bangumiHasToken
                        ? (_bangumiEnabled ? '已开启' : '已配置')
                        : '未配置',
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
                    title: 'WebDAV 多端同步',
                    subtitle: '通过自己的网盘与其他设备接着看',
                    status: _webdavHasConfig
                        ? (_webdavEnabled ? '已开启' : '已配置')
                        : '未配置',
                    statusColor:
                        _webdavHasConfig ? Colors.green : colors.outline,
                    iconBg: colors.tertiaryContainer,
                    iconFg: colors.onTertiaryContainer,
                    onTap: () async {
                      await context.pushNamed('/settings/webdav/');
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),

                  _SyncServiceTile(
                    icon: Icons.wb_twilight_rounded,
                    title: '樱花动漫',
                    subtitle: '云端同步你的追番数据',
                    status: AuthService.isLoggedIn ? '已登录' : '未登录',
                    statusColor:
                        AuthService.isLoggedIn ? Colors.green : colors.outline,
                    iconBg: colors.secondaryContainer,
                    iconFg: colors.onSecondaryContainer,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => KazumiLoginPage()),
                      );
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
                                    Text('单向同步',
                                        style: text.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('上传：本机→云端；下载：云端→本机（均覆盖）',
                                        style: text.bodySmall?.copyWith(
                                            color: colors.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              // 上传 / 下载 两个按钮
                              FilledButton.tonalIcon(
                                onPressed: _busy
                                    ? null
                                    : () => _oneWaySync(upload: true),
                                icon: const Icon(Icons.upload_rounded, size: 16),
                                label: const Text('上传'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonalIcon(
                                onPressed: _busy
                                    ? null
                                    : () => _oneWaySync(upload: false),
                                icon: const Icon(Icons.download_rounded, size: 16),
                                label: const Text('下载'),
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
                        // 展开区：4 个开关
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: Column(
                              children: [
                                const Divider(height: 1),
                                _switchTile(
                                  title: '观看记录',
                                  subtitle: '观看进度与历史',
                                  value: _incHistory,
                                  onChanged: (v) {
                                    setState(() => _incHistory = v);
                                    GStorage.putSetting(
                                        SettingsKeys.oneWaySyncHistory, v);
                                  },
                                ),
                                _switchTile(
                                  title: '收藏',
                                  subtitle: '所有追番分类',
                                  value: _incCollect,
                                  onChanged: (v) {
                                    setState(() => _incCollect = v);
                                    GStorage.putSetting(
                                        SettingsKeys.oneWaySyncCollect, v);
                                  },
                                ),
                                _switchTile(
                                  title: '弹幕规则',
                                  subtitle: '弹幕屏蔽词',
                                  value: _incDanmaku,
                                  onChanged: (v) {
                                    setState(() => _incDanmaku = v);
                                    GStorage.putSetting(
                                        SettingsKeys.oneWaySyncDanmaku, v);
                                  },
                                ),
                                _switchTile(
                                  title: '追番目标',
                                  subtitle: '本周观看目标',
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

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/storage/storage.dart';

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  bool get _bangumiHasToken => GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;
  bool get _bangumiEnabled => GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
  bool get _webdavHasConfig => GStorage.getSetting(SettingsKeys.webDavURL).trim().isNotEmpty;
  bool get _webdavEnabled => GStorage.getSetting(SettingsKeys.webDavEnable);

  // 同步缓存：上次同步时间戳
  int _lastSyncTime = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text('同步设置', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
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
                  Text('选择需要的服务', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('也可以同时使用多个服务来同步数据', style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 16),

                  _SyncServiceTile(
                    icon: Icons.brightness_6_rounded,
                    title: 'Bangumi 追番同步',
                    subtitle: '与Bangumi保持相同的追番状态',
                    status: _bangumiHasToken ? (_bangumiEnabled ? '已开启' : '已配置') : '未配置',
                    statusColor: _bangumiHasToken ? Colors.green : colors.outline,
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
                    status: _webdavHasConfig ? (_webdavEnabled ? '已开启' : '已配置') : '未配置',
                    statusColor: _webdavHasConfig ? Colors.green : colors.outline,
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
                    statusColor: AuthService.isLoggedIn ? Colors.green : colors.outline,
                    iconBg: colors.secondaryContainer,
                    iconFg: colors.onSecondaryContainer,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const KazumiLoginPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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

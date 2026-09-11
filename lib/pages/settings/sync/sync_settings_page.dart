import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/sync/bangumi_sync_service.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 同步设置页面 - 三个大模块
/// 1. Bangumi追番同步
/// 2. WebDAV多端同步
/// 3. 樱花动漫同步
class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  final _bangumi = BangumiSyncService();
  bool _bangumiExpanded = false;
  bool _webdavExpanded = false;
  bool _yhdmgzExpanded = false;

  bool get _bangumiEnabled => GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
  bool get _webdavEnabled => GStorage.getSetting(SettingsKeys.webDavEnable);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text(
          '同步设置',
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        needTopOffset: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 介绍
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('选择需要的服务',
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('也可以同时使用多个服务',
                            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 1. Bangumi追番同步 ──
                  _buildBangumiModule(colors, text),
                  const SizedBox(height: 12),

                  // ── 2. WebDAV多端同步 ──
                  _buildWebDavModule(colors, text),
                  const SizedBox(height: 12),

                  // ── 3. 樱花动漫同步 ──
                  _buildYhdmgzModule(colors, text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Bangumi模块 ──
  Widget _buildBangumiModule(ColorScheme colors, TextTheme text) {
    final configured = GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;
    final statusLabel = configured ? '已配置' : '未配置';
    final statusColor = configured ? Colors.green : colors.outline;
    final statusIcon = configured ? Icons.check_circle_outline_rounded : Icons.help_outline_rounded;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 头部
          InkWell(
            onTap: () => setState(() => _bangumiExpanded = !_bangumiExpanded),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.brightness_6_rounded, color: colors.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bangumi 追番同步',
                                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('与Bangumi保持相同的追番状态',
                                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: colors.onSurfaceVariant,
                          size: 28),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 状态指示
                  Row(
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 6),
                      Text(statusLabel,
                          style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (configured)
                        TextButton.icon(
                          onPressed: () => context.pushNamed('/settings/bangumi/'),
                          icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                          label: const Text('管理追番同步'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 展开内容
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 12),
                  Text('支持的功能：',
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _buildFeatureItem(text, colors, Icons.sync, '自动同步追番状态'),
                  _buildFeatureItem(text, colors, Icons.favorite, '同步收藏列表'),
                  _buildFeatureItem(text, colors, Icons.history, '同步观看进度'),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () => context.pushNamed('/settings/bangumi/'),
                    child: const Text('进入设置'),
                  ),
                ],
              ),
            ),
            crossFadeState: _bangumiExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  // ── WebDAV模块 ──
  Widget _buildWebDavModule(ColorScheme colors, TextTheme text) {
    final statusLabel = _webdavEnabled ? '已开启' : '未配置';
    final statusColor = _webdavEnabled ? Colors.green : colors.outline;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _webdavExpanded = !_webdavExpanded),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.tertiaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.cloud_sync_rounded, color: colors.onTertiaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('WebDAV 多端同步',
                                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('通过自己的网盘与其他设备接着看',
                                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: colors.onSurfaceVariant, size: 28),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: statusColor),
                      const SizedBox(width: 6),
                      Text(statusLabel,
                          style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_webdavEnabled)
                        TextButton.icon(
                          onPressed: () => context.pushNamed('/settings/webdav/'),
                          icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                          label: const Text('管理'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 12),
                  Text('同步内容：',
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _buildFeatureItem(text, colors, Icons.history, '观看记录'),
                  _buildFeatureItem(text, colors, Icons.favorite, '收藏列表'),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () => context.pushNamed('/settings/webdav/'),
                    child: const Text('配置 WebDAV'),
                  ),
                ],
              ),
            ),
            crossFadeState: _webdavExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  // ── 樱花动漫模块 ──
  Widget _buildYhdmgzModule(ColorScheme colors, TextTheme text) {
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _yhdmgzExpanded = !_yhdmgzExpanded),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.wb_twilight_rounded, color: colors.onSecondaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('樱花动漫',
                                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('云端同步你的追番数据',
                                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: colors.onSurfaceVariant, size: 28),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        AuthService.isLoggedIn ? Icons.check_circle : Icons.help_outline,
                        size: 16,
                        color: AuthService.isLoggedIn ? Colors.green : colors.outline,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AuthService.isLoggedIn ? '已登录' : '未登录',
                        style: TextStyle(
                          fontSize: 12,
                          color: AuthService.isLoggedIn ? Colors.green : colors.outline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 12),
                  Text('同步内容：',
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _buildFeatureItem(text, colors, Icons.favorite, '收藏列表'),
                  _buildFeatureItem(text, colors, Icons.history, '观看记录'),
                  _buildFeatureItem(text, colors, Icons.people, '好友数据'),
                ],
              ),
            ),
            crossFadeState: _yhdmgzExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(TextTheme text, ColorScheme colors, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Text(label, style: text.bodyMedium),
        ],
      ),
    );
  }
}

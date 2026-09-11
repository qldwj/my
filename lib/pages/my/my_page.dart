import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/settings_section_card.dart';
import 'package:kazumi/pages/my/bangumi_login_page.dart';
import 'package:kazumi/pages/my/kazumi_login_page.dart';
import 'package:kazumi/pages/my/qrcode_login_page.dart';
import 'package:kazumi/pages/my/privacy_settings_page.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:qr_flutter/qr_flutter.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  String _bangumiAvatarUrl = '';
  String _bangumiName = '';
  bool _bangumiLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _bangumiLoggedIn = GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;
    if (_bangumiLoggedIn) _loadBangumiUser();
  }

  Future<void> _loadBangumiUser() async {
    try {
      final user = await BangumiApi.getCurrentUser();
      if (user != null && mounted) {
        setState(() {
          _bangumiAvatarUrl = user.avatar.large;
          _bangumiName = user.nickname.isNotEmpty ? user.nickname : user.username;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          // 右上角二维码
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: '二维码',
            onPressed: () => _showShareQrcode(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── 用户信息卡片 ──
          _buildUserCard(cs),
          const SizedBox(height: 12),

          // ── 历史记录 & 下载 ──
          SettingsSectionCard(
            title: '观看',
            children: [
              SettingsEntryTile(
                icon: Icons.history_rounded,
                title: '历史记录',
                onTap: () => context.pushNamed('/history/'),
              ),
              SettingsEntryTile(
                icon: Icons.download_rounded,
                title: '离线下载',
                onTap: () => context.pushNamed('/settings/download-settings'),
              ),
            ],
          ),

          // ── 数据管理 ──
          SettingsSectionCard(
            title: '数据管理',
            children: [
              SettingsEntryTile(
                icon: Icons.rule_rounded,
                title: '规则管理',
                description: '管理番剧资源规则',
                onTap: () => context.pushNamed('/settings/plugin/'),
              ),
              SettingsEntryTile(
                icon: Icons.sync_rounded,
                title: '同步备份',
                description: 'WebDAV 同步收藏与历史',
                onTap: () => context.pushNamed('/settings/webdav/'),
              ),
              SettingsEntryTile(
                icon: Icons.cleaning_services_rounded,
                title: '清除缓存',
                onTap: () => _showClearCacheDialog(context),
              ),
            ],
          ),

          // ── 设置 ──
          SettingsSectionCard(
            title: '设置',
            children: [
              SettingsEntryTile(
                icon: Icons.settings_rounded,
                title: '设置',
                description: '播放器、下载、外观等设置',
                onTap: () => context.pushNamed('/settings'),
              ),
              SettingsEntryTile(
                icon: Icons.info_outline_rounded,
                title: '关于',
                onTap: () => context.pushNamed('/settings/about/'),
              ),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildUserCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _bangumiLoggedIn
            ? Row(
                children: [
                  // 头像
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.surfaceContainerHighest,
                    backgroundImage: _bangumiAvatarUrl.isNotEmpty
                        ? NetworkImage(_bangumiAvatarUrl)
                        : null,
                    child: _bangumiAvatarUrl.isEmpty
                        ? Icon(Icons.person, size: 28, color: cs.outline)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // 用户名
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _bangumiName.isNotEmpty ? _bangumiName : 'Bangumi 用户',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bangumi 已登录',
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                  // 隐私设置（右上角齿轮）
                  IconButton(
                    icon: const Icon(Icons.privacy_tip_rounded, size: 20),
                    tooltip: '隐私设置',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PrivacySettingsPage()),
                      );
                    },
                  ),
                ],
              )
            : Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Icon(Icons.person_add_rounded, size: 28, color: cs.outline),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '未登录',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '登录以同步收藏和历史',
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _showLoginOptions(context),
                    child: const Text('登录'),
                  ),
                ],
              ),
      ),
    );
  }

  void _showLoginOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: const Text('Bangumi 一键登录'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BangumiLoginPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_rounded),
              title: const Text('樱花动漫账号'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const KazumiLoginPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_rounded),
              title: const Text('二维码登录'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QRCodeLoginPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showShareQrcode(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('扫码打开 Kazumi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: 'https://qlyyz.xyz',
              size: 200,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 12),
            Text(
              '使用手机浏览器扫描二维码',
              style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    KazumiDialog.show(
      builder: (ctx) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存数据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              KazumiDialog.showToast(message: '缓存已清除');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

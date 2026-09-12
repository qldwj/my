import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/services/sync/bangumi_sync_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:url_launcher/url_launcher.dart';

class BangumiSyncPage extends StatefulWidget {
  const BangumiSyncPage({super.key});

  @override
  State<BangumiSyncPage> createState() => _BangumiSyncPageState();
}

class _BangumiSyncPageState extends State<BangumiSyncPage> {
  final _tokenController = TextEditingController();
  final _bangumi = BangumiSyncService();
  bool _expanded = true;
  bool _syncEnabled = false;

  @override
  void initState() {
    super.initState();
    _syncEnabled = GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    _tokenController.text = GStorage.getSetting(SettingsKeys.bangumiAccessToken);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  bool get _hasToken => _tokenController.text.trim().isNotEmpty;
  bool get _isVerified => _bangumi.initialized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text(
          'Bangumi 同步',
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        needTopOffset: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
                        Text('让追番保持同步',
                            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text('与 Bangumi 保持相同的追番状态，支持想看/在看/看过/搁置/抛弃。',
                            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 连接配置区
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(28),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Icon(Icons.key_rounded, color: colors.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('连接配置', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _isVerified ? '已连接 · ${_bangumi.username}' : '未连接',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _isVerified ? Colors.green : colors.outline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                  color: colors.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Divider(),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _tokenController,
                                  decoration: InputDecoration(
                                    labelText: 'Access Token',
                                    hintText: '从 Bangumi 获取',
                                    filled: true,
                                    fillColor: colors.surfaceContainerHighest,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: _isVerified ? null : () async {
                                        // 先保存token到存储
                                        final token = _tokenController.text.trim();
                                        if (token.isEmpty) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('请输入Access Token')),
                                          );
                                          return;
                                        }
                                        await GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
                                        try {
                                          await _bangumi.init();
                                          // 验证成功后自动开启同步
                                          setState(() {
                                            _syncEnabled = true;
                                          });
                                          await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('连接成功，已自动开启同步')),
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('连接失败: $e')),
                                            );
                                          }
                                        }
                                      },
                                      child: Text(_isVerified ? '已验证' : '验证并保存'),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () async {
                                        final uri = Uri.parse('https://next.bgm.tv/demo/access-token/create');
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                                        }
                                      },
                                      child: const Text('获取授权码'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 300),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 自动同步开关
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(28),
                    child: SwitchListTile(
                      title: const Text('自动同步'),
                      subtitle: const Text('修改追番状态时自动同步到 Bangumi'),
                      value: _syncEnabled,
                      onChanged: (value) {
                        setState(() => _syncEnabled = value);
                        GStorage.putSetting(SettingsKeys.bangumiSyncEnable, value);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 立即同步按钮
                  if (_isVerified)
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          await _bangumi.syncCollectibles();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('同步完成')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('同步失败: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('立即同步追番'),
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

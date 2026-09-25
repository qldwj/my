import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/danmaku/danmaku_shield_sync.dart';
import 'package:kazumi/repositories/danmaku_shield_repository.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/webdav.dart';

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _webDavEnable = false;
  bool _enableHistory = true;
  bool _enableCollect = true;
  bool _enableDanmakuShield = true;
  bool _testing = false;
  bool _passwordVisible = false;
  bool _uploading = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _webDavEnable = GStorage.getSetting(SettingsKeys.webDavEnable);
    _enableHistory = GStorage.getSetting(SettingsKeys.webDavEnableHistory);
    _enableCollect = GStorage.getSetting(SettingsKeys.webDavEnableCollect);
    _enableDanmakuShield =
        GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield);
    _urlController.text = GStorage.getSetting(SettingsKeys.webDavURL);
    _userController.text = GStorage.getSetting(SettingsKeys.webDavUsername);
    _passController.text = GStorage.getSetting(SettingsKeys.webDavPassword);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (_urlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置服务器地址')),
      );
      return;
    }
    setState(() => _testing = true);
    try {
      await GStorage.putSetting(SettingsKeys.webDavURL, _urlController.text.trim());
      await GStorage.putSetting(SettingsKeys.webDavUsername, _userController.text.trim());
      await GStorage.putSetting(SettingsKeys.webDavPassword, _passController.text.trim());
      await WebDav().init();
      await WebDav().ping();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接成功')),
        );
        setState(() => _webDavEnable = true);
        await GStorage.putSetting(SettingsKeys.webDavEnable, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 🆕 手动上传弹幕规则（仅推送本设备，不拉远端）
  Future<void> _uploadDanmakuRules() async {
    if (!mounted) return;
    if (_urlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置并测试WebDAV连接')),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      await GStorage.putSetting(SettingsKeys.webDavURL, _urlController.text.trim());
      await GStorage.putSetting(SettingsKeys.webDavUsername, _userController.text.trim());
      await GStorage.putSetting(SettingsKeys.webDavPassword, _passController.text.trim());

      final webDav = WebDav();
      await webDav.init();

      final repo = inject<IDanmakuShieldRepository>();
      final deviceId = await repo.getDeviceId();
      if (deviceId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未获取到设备ID，请重试')),
          );
        }
        return;
      }

      // 构造当前设备规则状态（用已有的 GStorage state 兜底，保持 deleted 状态）
      var state = DanmakuShieldSyncState();
      final saved = GStorage.getSetting(SettingsKeys.danmakuShieldSyncState);
      if (saved.isNotEmpty) {
        try {
          state = DanmakuShieldSyncState.decode(saved);
        } catch (_) {}
      }
      // 把本地当前 rules 合并进来（新规则会进，删除的状态保持）
      final localEntries = <DanmakuShieldSyncEntry>[];
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (final rule in repo.getRules()) {
        localEntries.add(DanmakuShieldSyncEntry(
          rule: rule,
          updatedAt: now,
          deviceId: deviceId,
          deleted: false,
        ));
      }
      if (localEntries.isNotEmpty) {
        state = state.merge(DanmakuShieldSyncState(localEntries));
      }
      if (state.entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('本地没有弹幕规则可上传')),
          );
        }
        return;
      }

      await webDav.uploadDanmakuShieldState(deviceId, state.encode());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('弹幕规则上传成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 🆕 手动下载弹幕规则（从云端拉取所有设备合并后覆盖本地）
  Future<void> _downloadDanmakuRules() async {
    if (!mounted) return;
    if (_urlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置并测试WebDAV连接')),
      );
      return;
    }
    setState(() => _downloading = true);
    try {
      await GStorage.putSetting(SettingsKeys.webDavURL, _urlController.text.trim());
      await GStorage.putSetting(SettingsKeys.webDavUsername, _userController.text.trim());
      await GStorage.putSetting(SettingsKeys.webDavPassword, _passController.text.trim());

      final webDav = WebDav();
      await webDav.init();

      final remote = await webDav.downloadDanmakuShieldState();
      if (remote == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('云端没有弹幕规则文件，请先从其他设备上传')),
          );
        }
        return;
      }

      final repo = inject<IDanmakuShieldRepository>();
      await repo.mergeSyncState(remote);
      final rules = repo.getRules();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功同步 ${rules.length} 条弹幕规则')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text('WebDAV 多端同步',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        needTopOffset: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 标题
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.devices_rounded, size: 28, color: colors.primary),
                            const SizedBox(width: 12),
                            Text('多设备同步', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('连接自己云盘，同步观看与收藏', style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 连接配置
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('连接你的云盘', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('需要支持WebDAV的云盘或服务器', style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            labelText: '服务器地址',
                            hintText: 'https://example.com/dav/',
                            filled: true,
                            fillColor: colors.surfaceContainerHighest,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _userController,
                          decoration: InputDecoration(
                            labelText: '用户名',
                            filled: true,
                            fillColor: colors.surfaceContainerHighest,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passController,
                          obscureText: !_passwordVisible,
                          decoration: InputDecoration(
                            labelText: '密码或应用授权码',
                            filled: true,
                            fillColor: colors.surfaceContainerHighest,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            suffixIcon: IconButton(
                              icon: Icon(_passwordVisible ? Icons.visibility_off : Icons.visibility, size: 20),
                              onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _testing ? null : _testConnection,
                            icon: _testing
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.wifi_find_rounded),
                            label: Text(_testing ? '测试中...' : '测试连接'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 同步内容
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('同步内容', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('观看记录'),
                          subtitle: const Text('自动同步观看进度与历史记录'),
                          value: _enableHistory,
                          onChanged: (v) {
                            setState(() => _enableHistory = v);
                            GStorage.putSetting(SettingsKeys.webDavEnableHistory, v);
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          title: const Text('收藏'),
                          subtitle: const Text('同步所有追番分类'),
                          value: _enableCollect,
                          onChanged: (v) {
                            setState(() => _enableCollect = v);
                            GStorage.putSetting(SettingsKeys.webDavEnableCollect, v);
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          title: const Text('弹幕屏蔽词'),
                          subtitle: const Text('多端同步屏蔽关键词（关键词云端同步）'),
                          value: _enableDanmakuShield,
                          onChanged: (v) {
                            setState(() => _enableDanmakuShield = v);
                            GStorage.putSetting(SettingsKeys.webDavEnableDanmakuShield, v);
                          },
                          contentPadding: EdgeInsets.zero,
                        ),

                        // 🆕 弹幕规则手动上传/下载（切换设备时使用）
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _uploading
                                    ? null
                                    : _uploadDanmakuRules,
                                icon: _uploading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child:
                                            CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.upload_file_rounded),
                                label: Text(_uploading
                                    ? '上传中...'
                                    : '一键上传弹幕规则'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _downloading
                                    ? null
                                    : _downloadDanmakuRules,
                                icon: _downloading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child:
                                            CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.download_rounded),
                                label: Text(_downloading
                                    ? '下载中...'
                                    : '一键下载弹幕规则'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '在设备间切换时手动同步，覆盖本地规则',
                          style: text.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 启动开关
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(28),
                    child: SwitchListTile(
                      title: const Text('启动 WebDAV 同步'),
                      subtitle: Text(_webDavEnable ? '已开启' : '连接测试通过后自动开启'),
                      value: _webDavEnable,
                      onChanged: (v) {
                        setState(() => _webDavEnable = v);
                        GStorage.putSetting(SettingsKeys.webDavEnable, v);
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
}

import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:kazumi/services/github/github_sync_service.dart';

class WebDavEditorPage extends StatefulWidget {
  const WebDavEditorPage({
    super.key,
  });

  @override
  State<WebDavEditorPage> createState() => _WebDavEditorPageState();
}

class _WebDavEditorPageState extends State<WebDavEditorPage> {
  final TextEditingController webDavURLController = TextEditingController();
  final TextEditingController webDavUsernameController =
      TextEditingController();
  final TextEditingController webDavPasswordController =
      TextEditingController();
  bool passwordVisible = false;
  bool _syncing = false;
  String _githubToken = '';
  int _lastSync = 0;

  @override
  void initState() {
    super.initState();
    webDavURLController.text = GStorage.getSetting(SettingsKeys.webDavURL);
    webDavUsernameController.text =
        GStorage.getSetting(SettingsKeys.webDavUsername);
    webDavPasswordController.text =
        GStorage.getSetting(SettingsKeys.webDavPassword);
    _githubToken = GStorage.getSetting('github_cloud_token') ?? '';
    _lastSync = GStorage.getSetting('github_last_sync') ?? 0;
  }

  @override
Future<void> _syncToGitHub() async {
    setState(() => _syncing = true);
    try {
      final results = await GitHubSyncService.syncToCloud();
      await GStorage.putSetting('github_last_sync', DateTime.now().millisecondsSinceEpoch);
      setState(() { _syncing = false; _lastSync = GStorage.getSetting('github_last_sync'); });
      final ok = results.values.every((v) => v);
      KazumiDialog.showToast(message: ok ? '同步成功' : '同步部分失败');
    } catch (e) {
      setState(() => _syncing = false);
      KazumiDialog.showToast(message: '同步失败: $e');
    }
  }

  Future<void> _syncFromGitHub() async {
    setState(() => _syncing = true);
    try {
      final results = await GitHubSyncService.syncFromCloud();
      setState(() => _syncing = false);
      KazumiDialog.showToast(message: results.isNotEmpty ? '恢复完成' : '无数据可恢复');
    } catch (e) {
      setState(() => _syncing = false);
      KazumiDialog.showToast(message: '恢复失败: $e');
    }
  }

  void dispose() {
    webDavURLController.dispose();
    webDavUsernameController.dispose();
    webDavPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(
        title: Text('WEBDAV编辑'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SizedBox(
            width: (MediaQuery.of(context).size.width > 1000) ? 1000 : null,
            child: Column(
              children: [
                TextField(
                  controller: webDavURLController,
                  decoration: const InputDecoration(
                      labelText: 'URL', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: webDavUsernameController,
                  decoration: const InputDecoration(
                      labelText: 'Username', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: webDavPasswordController,
                  obscureText: !passwordVisible,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          passwordVisible = !passwordVisible;
                        });
                      },
                      icon: Icon(passwordVisible
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded),
                    ),
                  ),
                ),
                // const SizedBox(height: 20),
                // ExpansionTile(
                //   title: const Text('高级选项'),
                //   children: [],
                // ),
                const SizedBox(height: 32),
                // ===== GitHub 仓库同步 =====
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.cloud_sync, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text('GitHub 仓库同步', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 12),
                        TextField(
                          controller: TextEditingController(text: _githubToken),
                          decoration: const InputDecoration(
                            labelText: 'GitHub Token',
                            hintText: 'ghp_xxx',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) async {
                            _githubToken = v;
                            await GStorage.putSetting('github_cloud_token', v);
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _syncing ? null : _syncToGitHub,
                              icon: _syncing
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.cloud_upload),
                              label: Text(_syncing ? '同步中...' : '上传到仓库'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _syncing ? null : _syncFromGitHub,
                              icon: const Icon(Icons.cloud_download),
                              label: const Text('从仓库恢复'),
                            ),
                          ),
                        ]),
                        if (_lastSync > 0) ...[
                          const SizedBox(height: 8),
                          Text('上次同步：${DateTime.fromMillisecondsSinceEpoch(_lastSync).toString().substring(0, 19)}',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.save),
        onPressed: () async {
          GStorage.putSetting(SettingsKeys.webDavURL, webDavURLController.text);
          GStorage.putSetting(
              SettingsKeys.webDavUsername, webDavUsernameController.text);
          GStorage.putSetting(
              SettingsKeys.webDavPassword, webDavPasswordController.text);
          var webDav = WebDav();
          try {
            await webDav.init();
          } catch (e) {
            KazumiDialog.showToast(message: '配置失败 ${e.toString()}');
            await GStorage.putSetting(SettingsKeys.webDavEnable, false);
            return;
          }
          KazumiDialog.showToast(message: '配置成功, 开始测试');
          try {
            await webDav.ping();
            KazumiDialog.showToast(message: '测试成功');
          } catch (e) {
            KazumiDialog.showToast(message: '测试失败 ${e.toString()}');
            await GStorage.putSetting(SettingsKeys.webDavEnable, false);
          }
        },
      ),
    );
  }
}

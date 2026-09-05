import 'package:flutter/material.dart';
import 'package:kazumi/services/github/github_sync_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';

/// GitHub 仓库同步设置页
class GitHubSyncPage extends StatefulWidget {
  const GitHubSyncPage({super.key});
  @override
  State<GitHubSyncPage> createState() => _GitHubSyncPageState();
}

class _GitHubSyncPageState extends State<GitHubSyncPage> {
  String _token = '';
  String _repo = 'yhdmjson';
  bool _syncing = false;
  int _lastSync = 0;

  @override
  void initState() {
    super.initState();
    _token = GitHubSyncService.token ?? '';
    _repo = GitHubSyncService.repo;
    _lastSync = GitHubSyncService.lastSync;
  }

  Future<void> _syncToCloud() async {
    setState(() => _syncing = true);
    final results = await GitHubSyncService.syncToCloud();
    await GitHubSyncService.updateLastSync();
    setState(() { _syncing = false; _lastSync = GitHubSyncService.lastSync; });
    final success = results.values.every((v) => v);
    KazumiDialog.showToast(message: success ? '同步成功' : '部分同步失败');
  }

  Future<void> _syncFromCloud() async {
    setState(() => _syncing = true);
    final results = await GitHubSyncService.syncFromCloud();
    setState(() => _syncing = false);
    KazumiDialog.showToast(message: results.isNotEmpty ? '恢复完成' : '无数据可恢复');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('仓库同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Token 输入
          Card(child: ListTile(
            leading: Icon(Icons.key, color: cs.primary),
            title: const Text('GitHub Token'),
            subtitle: Text(_token.isEmpty ? '未配置' : '已配置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final ctrl = TextEditingController(text: _token);
              final result = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('设置 GitHub Token'),
                  content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'ghp_xxx', border: OutlineInputBorder())),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('保存')),
                  ],
                ),
              );
              if (result != null) {
                await GitHubSyncService.saveToken(result);
                setState(() => _token = result);
              }
            },
          )),
          const SizedBox(height: 12),
          // 仓库名
          Card(child: ListTile(
            leading: Icon(Icons.folder, color: cs.secondary),
            title: const Text('仓库名'),
            subtitle: Text(_repo),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final ctrl = TextEditingController(text: _repo);
              final result = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('设置仓库名'),
                  content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'yhdmjson', border: OutlineInputBorder())),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('保存')),
                  ],
                ),
              );
              if (result != null && result.isNotEmpty) {
                await GitHubSyncService.saveRepo(result);
                setState(() => _repo = result);
              }
            },
          )),
          const SizedBox(height: 24),
          // 同步按钮
          Row(children: [
            Expanded(child: FilledButton.icon(
              onPressed: _syncing ? null : _syncToCloud,
              icon: _syncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload),
              label: const Text('上传到仓库'),
            )),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(
              onPressed: _syncing ? null : _syncFromCloud,
              icon: const Icon(Icons.cloud_download),
              label: const Text('从仓库恢复'),
            )),
          ]),
          const SizedBox(height: 16),
          // 最后同步时间
          if (_lastSync > 0)
            Text('上次同步：${DateTime.fromMillisecondsSinceEpoch(_lastSync).toString().substring(0, 19)}',
              style: TextStyle(fontSize: 12, color: cs.outline)),
        ],
      ),
    );
  }
}

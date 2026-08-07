import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';

/// 同步日志 - 记录每次同步的详细结果
class SyncLogEntry {
  final DateTime time;
  final String type; // 'upload' | 'download' | 'error' | 'info'
  final String message;
  final Map<String, dynamic>? detail;

  SyncLogEntry(this.time, this.type, this.message, {this.detail});
}

/// 同步日志页面
class SyncLogPage extends StatefulWidget {
  const SyncLogPage({super.key});

  @override
  State<SyncLogPage> createState() => _SyncLogPageState();
}

class _SyncLogPageState extends State<SyncLogPage> {
  final List<SyncLogEntry> _logs = [];
  bool _running = false;

  void _addLog(String type, String msg, {Map<String, dynamic>? detail}) {
    setState(() {
      _logs.insert(0, SyncLogEntry(DateTime.now(), type, msg, detail: detail));
    });
    KazumiLogger().i('SyncLog: [$type] $msg${detail != null ? ' | $detail' : ''}');
  }

  Future<void> _runSync() async {
    if (_running) return;
    setState(() => _running = true);
    _addLog('info', '=== 开始同步 ===');

    // 1. 检查登录状态
    final token = AuthService.getLocalToken();
    if (token == null) {
      _addLog('error', '✗ 未登录樱花账号');
      setState(() => _running = false);
      return;
    }
    _addLog('info', '✓ 已登录樱花账号');

    // 2. 读取本地收藏
    final localCollect = GStorage.collectibles.values.toList();
    _addLog('info', '本地收藏: ${localCollect.length} 项',
        detail: {'ids': localCollect.map((c) => c.bangumiItem.id).toList()});

    // 3. 构造上传数据
    final collectData = localCollect.map((c) => ({
      'id': c.bangumiItem.id,
      'name': c.bangumiItem.name,
      'name_cn': c.bangumiItem.nameCn,
      'type': c.type,
      'time': c.time.toIso8601String(),
      'image': c.bangumiItem.images['large'] ?? '',
    })).toList();
    _addLog('info', '正在上传 ${collectData.length} 项到服务器...');

    // 4. 发送同步请求
    try {
      final stopwatch = Stopwatch()..start();
      final res = await AuthService.syncData({'collect': collectData}).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _addLog('error', '✗ 请求超时(30s)');
          setState(() => _running = false);
          return {'error': '请求超时'};
        },
      );
      stopwatch.stop();

      _addLog('info', '服务器响应耗时: ${stopwatch.elapsedMilliseconds}ms');

      if (res['error'] != null) {
        _addLog('error', '✗ 服务器返回错误: ${res['error']}',
            detail: {'完整响应': res});
        setState(() => _running = false);
        return;
      }

      _addLog('info', '✓ 上传成功',
          detail: {'响应': res});

      // 5. 处理服务器返回的合并数据
      if (res['sync_data'] is Map) {
        final serverData = res['sync_data'] as Map;
        if (serverData['collect'] is List) {
          final remoteList = serverData['collect'] as List;
          _addLog('info', '服务器数据: ${remoteList.length} 项');

          int downloadCount = 0;
          for (final item in remoteList) {
            if (item is Map) {
              final remoteId = item['id'];
              if (remoteId is! int) continue;
              final exists = localCollect.any((c) => c.bangumiItem.id == remoteId);
              if (!exists) {
                final bangumiItem = BangumiItem(
                  id: remoteId,
                  type: 0,
                  name: item['name']?.toString() ?? '未知',
                  nameCn: item['name_cn']?.toString() ?? '',
                  summary: '',
                  airDate: '',
                  airWeekday: 0,
                  rank: 0,
                  images: {'large': item['image']?.toString() ?? ''},
                  tags: [],
                  alias: [],
                  ratingScore: 0.0,
                  votes: 0,
                  votesCount: [],
                  info: '',
                );
                await GStorage.putCollectible(
                  CollectedBangumi(bangumiItem, DateTime.now(),
                    item['type'] is int ? item['type'] as int : 1),
                );
                downloadCount++;
                _addLog('download', '↓ 下载: ${item['name']} (id=$remoteId)');
              }
            }
          }
          _addLog('info', '✓ 同步完成: 上传 ${collectData.length} 项，下载 $downloadCount 项');
        }
      } else {
        _addLog('error', '✗ 服务器未返回 sync_data',
            detail: {'完整响应': res});
      }
    } on TimeoutException {
      _addLog('error', '✗ 同步超时(30s)');
    } catch (e, st) {
      _addLog('error', '✗ 同步异常: $e',
          detail: {'stack': st.toString().substring(0, 200)});
    }

    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('同步诊断'),
        actions: [
          IconButton(
            onPressed: _running ? null : _runSync,
            icon: _running
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            tooltip: '执行同步',
          ),
          IconButton(
            onPressed: () => setState(() => _logs.clear()),
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空日志',
          ),
        ],
      ),
      body: _logs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('暂无日志，点击右上角 ▶ 开始诊断同步',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                final icon = switch (log.type) {
                  'error' => Icons.error,
                  'download' => Icons.download,
                  'info' => Icons.info_outline,
                  _ => Icons.circle,
                };
                final color = switch (log.type) {
                  'error' => Colors.red,
                  'download' => Colors.blue,
                  _ => colorScheme.onSurface,
                };
                return Card(
                  margin: const EdgeInsets.only(bottom: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}',
                                style: TextStyle(fontSize: 11, color: colorScheme.outline),
                              ),
                              const SizedBox(height: 2),
                              Text(log.message, style: TextStyle(fontSize: 13)),
                              if (log.detail != null) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    const JsonEncoder.withIndent('  ').convert(log.detail),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

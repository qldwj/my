import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/utils/date_time.dart';

/// 登录设备管理：查看已登录设备、踢下线
class DeviceSessionsPage extends StatefulWidget {
  const DeviceSessionsPage({super.key});

  @override
  State<DeviceSessionsPage> createState() => _DeviceSessionsPageState();
}

class _DeviceSessionsPageState extends State<DeviceSessionsPage> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  bool _kicking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await AuthService.sessionList();
    if (!mounted) return;
    setState(() {
      _sessions = list;
      _loading = false;
    });
  }

  Future<void> _kick(Map<String, dynamic> session) async {
    final token = session['token']?.toString() ?? '';
    if (token.isEmpty) return;
    final confirm = await KazumiDialog.show<bool>(
      builder: (context) => AlertDialog(
        title: const Text('踢下线'),
        content: Text('确定让设备「${session['device_name'] ?? '未知设备'}」下线吗？'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('踢下线'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _kicking = true);
    final error = await AuthService.sessionKick(token);
    if (!mounted) return;
    setState(() => _kicking = false);
    if (error == null) {
      KazumiDialog.showToast(message: '✅ 已将该设备踢下线');
      _load();
    } else {
      KazumiDialog.showToast(message: '❌ $error');
    }
  }

  String _fmtTime(int ts) {
    if (ts <= 0) return '';
    return dateFormat(ts);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('登录设备管理'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(
                  child: GeneralEmptyState(
                    icon: Icons.devices_other_rounded,
                    title: '暂无登录设备',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final s = _sessions[index];
                    final isCurrent = s['is_current'] == 1;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.phone_android_rounded
                              : Icons.devices_other_rounded,
                          color: isCurrent
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s['device_name']?.toString() ?? '未知设备',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '当前设备',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onPrimaryContainer),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('登录：${_fmtTime((s['created_at'] as num?)?.toInt() ?? 0)}'),
                              if ((s['last_seen'] as num?)?.toInt() != null)
                                Text('最后活跃：${_fmtTime((s['last_seen'] as num?)?.toInt() ?? 0)}'),
                            ],
                          ),
                        ),
                        trailing: isCurrent
                            ? null
                            : IconButton(
                                tooltip: '踢下线',
                                icon: Icon(Icons.logout_rounded,
                                    color: colorScheme.error),
                                onPressed: _kicking ? null : () => _kick(s),
                              ),
                      ),
                    );
                  },
                ),
    );
  }
}

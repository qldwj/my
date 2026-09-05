import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/my/device_sessions_page.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';

/// 账号安全中心（我的 → 账号与数据 → 安全中心）
///
/// - 最近登录记录（IP / 设备 / 时间）
/// - 登录设备管理入口
class SecurityCenterPage extends StatefulWidget {
  const SecurityCenterPage({super.key});
  @override
  State<SecurityCenterPage> createState() => _SecurityCenterPageState();
}

class _SecurityCenterPageState extends State<SecurityCenterPage> {
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs = await AuthService.loginLogs();
    final sessions = await AuthService.sessionList();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _sessions = sessions;
      _loading = false;
    });
  }

  String _formatTime(int ts) {
    if (ts <= 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal().toString();
  }

  String _maskIp(String ip) {
    if (ip.length < 8) return ip;
    // 掩码中间部分：192.168.1.1 → 192.***.1.1
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.***.${parts[2]}.${parts[3]}';
    }
    return ip;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号安全中心'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 最近登录记录
                Text('最近登录记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
                const SizedBox(height: 4),
                Text('如发现异常登录，请及时修改账号或退出未知设备',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
                const SizedBox(height: 12),
                if (_logs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    child: const Center(child: Text('暂无登录记录')),
                  )
                else
                  ..._logs.map((log) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Icon(Icons.login, size: 20, color: cs.primary),
                          ),
                          title: Text(_maskIp(log['ip'] ?? '未知IP'),
                            style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            '${log['device_name'] ?? '未知设备'}\n${_formatTime((log['created_at'] as num?)?.toInt() ?? 0)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          isThreeLine: true,
                        ),
                      )),

                const SizedBox(height: 24),

                // 登录设备管理入口
                Text('登录设备', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
                const SizedBox(height: 12),
                if (_sessions.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    child: const Center(child: Text('暂无登录设备')),
                  )
                else
                  ..._sessions.take(5).map((s) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.devices_rounded, size: 20),
                        title: Text(s['device_name'] ?? '未知设备',
                          style: const TextStyle(fontSize: 14)),
                        subtitle: Text(_formatTime((s['last_seen'] as num?)?.toInt() ?? 0),
                          style: TextStyle(fontSize: 11, color: cs.outline)),
                      )),

                if (_sessions.length > 5)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DeviceSessionsPage(),
                        ),
                      );
                    },
                    child: const Text('查看全部设备 →'),
                  ),
              ],
            ),
    );
  }
}
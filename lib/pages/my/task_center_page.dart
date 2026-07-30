import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/services/auth_service.dart';

class TaskCenterPage extends StatefulWidget {
  const TaskCenterPage({super.key});

  @override
  State<TaskCenterPage> createState() => _TaskCenterPageState();
}

class _TaskCenterPageState extends State<TaskCenterPage> {
  int _coins = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final token = AuthService.getLocalToken();
    if (token == null) return;
    try {
      final c = HttpClient();
      final r = await c.getUrl(Uri.parse('https://qlyyz.xyz/api/chat?action=coins'));
      r.headers.set('Authorization', 'Bearer $token');
      final res = await r.close();
      final body = await res.transform(utf8.decoder).join();
      c.close();
      final data = jsonDecode(body) as Map;
      if (data['coins'] is int) setState(() => _coins = data['coins'] as int);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        // ⭐ 返回按钮返回到「其他设置」SettingsPage
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('任务中心'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 金币卡片
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.amber.shade300, Colors.orange.shade500]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(Icons.monetization_on, size: 48, color: Colors.white),
                const SizedBox(height: 8),
                Text('$_coins', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text('当前金币', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 看番赚金币
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.play_circle, color: cs.primary),
                  const SizedBox(width: 8),
                  const Text('看番赚金币', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                const Text('每看 5 分钟 +10 金币，自动到账'),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: (_coins % 50) / 50),
                const SizedBox(height: 4),
                Text('下一奖励: ${50 - (_coins % 50)} 金币', style: TextStyle(fontSize: 12, color: cs.outline)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 聊天任务
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.chat, color: cs.primary),
                  const SizedBox(width: 8),
                  const Text('聊天任务', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                const Text('每天首次发言 +20 金币（实际扣 1 发 1 条）'),
                const SizedBox(height: 8),
                const Text('分享动漫或规则不扣金币'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
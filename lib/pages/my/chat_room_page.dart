import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/encoding.dart';
import 'package:flutter_modular/flutter_modular.dart' show inject;

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({super.key});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  int _coins = 0;
  Timer? _pollTimer;
  static const _chatApi = 'https://qlyyz.xyz/api/chat';

  @override
  void initState() {
    super.initState();
    _loadCoins();
    _loadMessages();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(String action, {Map<String, dynamic>? body}) async {
    final token = AuthService.getLocalToken();
    if (token == null) return {'error': '未登录'};
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final url = Uri.parse('$_chatApi?action=$action');
      final request = body != null ? await client.postUrl(url) : await client.getUrl(url);
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.set('Content-Type', 'application/json');
      if (body != null) request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final resp = await response.transform(utf8.decoder).join();
      client.close();
      return jsonDecode(resp) as Map<String, dynamic>;
    } catch (e) {
      return {'error': '$e'};
    }
  }

  Future<void> _loadMessages() async {
    final res = await _request('msg');
    if (res['messages'] is List) {
      setState(() => _messages = (res['messages'] as List).cast<Map<String, dynamic>>());
    }
  }

  Future<void> _loadCoins() async {
    final res = await _request('coins');
    if (res['coins'] is int) setState(() => _coins = res['coins'] as int);
  }

  Future<void> _sendMessage({String? type, String? refId, String? shareName}) async {
    String msg;
    if (type == 'anime') {
      msg = '📺 分享了动漫：${shareName ?? '未知'}';
    } else if (type == 'rule') {
      msg = '🧩 分享了一个规则';
    } else {
      msg = _msgController.text.trim();
      if (msg.isEmpty) return;
      if (msg.length > 100) { KazumiDialog.showToast(message: '消息不能超过100字'); return; }
    }
    _msgController.clear();
    final body = <String, dynamic>{
      'message': msg,
      if (type != null) 'msg_type': type,
      if (refId != null) 'ref_id': refId,
    };
    final res = await _request('send', body: body);
    if (res['coins'] is int) setState(() => _coins = res['coins'] as int);
    if (res['error'] != null) KazumiDialog.showToast(message: '${res['error']}');
    await _loadMessages();
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  void _showShareSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.movie),
            title: const Text('分享收藏的动漫'),
            onTap: () { Navigator.pop(ctx); _showAnimePicker(); },
          ),
          ListTile(
            leading: const Icon(Icons.extension),
            title: const Text('分享已添加的规则'),
            onTap: () { Navigator.pop(ctx); _showRulePicker(); },
          ),
        ]),
      ),
    );
  }

  void _showAnimePicker() {
    final collects = GStorage.collectibles.values.toList();
    if (collects.isEmpty) { KazumiDialog.showToast(message: '暂无收藏'); return; }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('选择要分享的动漫', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: collects.length,
              itemBuilder: (_, i) {
                final c = collects[i];
                return ListTile(
                  leading: Icon(Icons.movie, color: Theme.of(context).colorScheme.primary),
                  title: Text(c.bangumiItem.nameCn.isNotEmpty ? c.bangumiItem.nameCn : c.bangumiItem.name),
                  subtitle: Text(c.bangumiItem.name),
                  onTap: () {
                    Navigator.pop(ctx);
                    final name = c.bangumiItem.nameCn.isNotEmpty ? c.bangumiItem.nameCn : c.bangumiItem.name;
                    _sendMessage(type: 'anime', refId: c.bangumiItem.id.toString(), shareName: name);
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _showRulePicker() {
    final ctrl = inject<PluginsController>();
    final rules = ctrl.pluginList.where((p) => !p.isCollection).toList();
    if (rules.isEmpty) { KazumiDialog.showToast(message: '暂无规则'); return; }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('选择要分享的规则', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: rules.length,
              itemBuilder: (_, i) {
                final r = rules[i];
                return ListTile(
                  leading: Icon(Icons.extension, color: Theme.of(context).colorScheme.primary),
                  title: Text(r.name),
                  onTap: () {
                    Navigator.pop(ctx);
                    final json = jsonEncode(r.toJson());
                    final b64 = base64Encode(utf8.encode(json));
                    _sendMessage(type: 'rule', refId: b64);
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _onTapMessage(Map<String, dynamic> msg) {
    final type = msg['msg_type'] as String? ?? 'text';
    final refId = msg['ref_id'] as String? ?? '';
    if (type == 'anime' && refId.isNotEmpty) {
      final id = int.tryParse(refId);
      if (id != null && rootNavigatorKey.currentContext != null) {
        final bangumiItem = BangumiItem(
          id: id, type: 0, name: '', nameCn: '', summary: '',
          airDate: '', airWeekday: 0, rank: 0, images: {}, tags: [], alias: [],
          ratingScore: 0.0, votes: 0, votesCount: [], info: '',
        );
        Navigator.of(rootNavigatorKey.currentContext!).pushNamed('/info/', arguments: bangumiItem);
      }
    } else if (type == 'rule' && refId.isNotEmpty) {
      try {
        final json = utf8.decode(base64Decode(refId));
        final data = jsonDecode(json) as Map<String, dynamic>;
        final plugin = Plugin.fromJson(data);
        inject<PluginsController>().updatePlugin(plugin);
        KazumiDialog.showToast(message: '规则已导入: ${plugin.name}');
      } catch (_) {
        KazumiDialog.showToast(message: '规则解析失败');
      }
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    final msgId = msg['id'];
    if (msgId == null) return;
    final confirm = await KazumiDialog.show<bool>(
      builder: (ctx) => AlertDialog(
        title: const Text('撤回消息'),
        content: const Text('确定撤回这条消息吗？'),
        actions: [
          TextButton(onPressed: () => KazumiDialog.dismiss(popWith: false), child: const Text('取消')),
          FilledButton(onPressed: () => KazumiDialog.dismiss(popWith: true), child: const Text('撤回')),
        ],
      ),
    );
    if (confirm != true) return;
    await _request('delete', body: {'msg_id': msgId});
    await _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('闲聊'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GestureDetector(
              onTap: _loadCoins,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.monetization_on, size: 18, color: Colors.amber),
                const SizedBox(width: 4),
                Text('$_coins', style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _messages.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('暂无消息', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ]))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: _messages.length,
                  itemBuilder: (ctx, i) {
                    final msg = _messages[i];
                    final type = msg['msg_type'] as String? ?? 'text';
                    final isShare = type == 'anime' || type == 'rule';
                    final isMine = msg['nickname'] == AuthService.getLocalToken() ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        onTap: isShare ? () => _onTapMessage(msg) : null,
                        onLongPress: () => _deleteMessage(msg),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CircleAvatar(radius: 16,
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text((msg['nickname'] as String? ?? '?')[0].toUpperCase(),
                              style: TextStyle(fontSize: 14, color: colorScheme.onPrimaryContainer)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(msg['nickname'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(width: 8),
                              Text(_formatTime(msg['created_at']), style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                            ]),
                            const SizedBox(height: 2),
                            if (type == 'anime')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.movie, size: 16),
                                  const SizedBox(width: 4),
                                  Text(msg['message'] ?? '📺 点击查看', style: TextStyle(fontSize: 13, color: colorScheme.primary)),
                                ]),
                              )
                            else if (type == 'rule')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.extension, size: 16),
                                  const SizedBox(width: 4),
                                  Text(msg['message'] ?? '🧩 点击导入', style: TextStyle(fontSize: 13, color: colorScheme.tertiary)),
                                ]),
                              )
                            else
                              Text(msg['message'] ?? '', style: const TextStyle(fontSize: 14)),
                          ])),
                        ]),
                      ),
                    );
                  },
                ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: SafeArea(top: false, child: Row(children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _showShareSheet,
                tooltip: '分享动漫或规则',
              ),
              const SizedBox(width: 4),
              Expanded(child: TextField(
                controller: _msgController,
                maxLength: 100,
                decoration: InputDecoration(
                  hintText: '输入消息（1金币/条）',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  counterText: '',
                  isDense: true,
                ),
                onSubmitted: (_) => _sendMessage(),
              )),
              const SizedBox(width: 4),
              IconButton.filled(onPressed: () => _sendMessage(), icon: const Icon(Icons.send_rounded)),
            ])),
          ),
        ],
      ),
    );
  }

  String _formatTime(dynamic ts) {
    if (ts is! int) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/my/chat_page.dart';
import 'package:kazumi/pages/my/chat_settings_page.dart';
import 'package:kazumi/services/social/social_service.dart';

/// 消息会话列表（最近聊天，微信式）
///
/// - 好友 + 最后一条消息 + 未读红点
/// - 打开期间每 30 秒轮询新消息 → 系统通知
class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  List<SocialConversation> _conversations = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_poll());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final convs = await SocialService.chatRecent();
    if (!mounted) return;
    setState(() {
      _conversations = convs;
      _loading = false;
    });
  }

  /// 轮询：拉新消息 → 通知 + 刷新未读
  Future<void> _poll() async {
    await SocialService.pollNewMessages();
    if (!mounted) return;
    final convs = await SocialService.chatRecent();
    if (!mounted) return;
    setState(() => _conversations = convs);
  }

  Future<void> _openChat(SocialConversation conv) async {
    final friend = SocialProfile(
      uid: conv.uid,
      nickname: conv.nickname,
      avatar: conv.avatar,
    );
    await Navigator.of(rootNavigatorKey.currentContext!).push(
      MaterialPageRoute(builder: (_) => ChatPage(friend: friend)),
    );
    // 返回后标记已读并刷新
    if (conv.lastId > 0) {
      await SocialService.markRead(conv.uid, conv.lastId);
    }
    _load();
  }

  String _timeText(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return hm;
    }
    if (dt.year == now.year) {
      return '${dt.month}/${dt.day}';
    }
    return '${dt.year}/${dt.month}/${dt.day}';
  }

  String _preview(SocialConversation c) {
    if (c.lastContent.isEmpty) return '还没有消息';
    switch (c.lastType) {
      case 'emoji':
        return c.lastContent;
      case 'anime':
        return '[番剧] $c.lastContent';
      case 'rule':
        return '[规则] $c.lastContent';
      case 'sync':
        return '[一起看] $c.lastContent';
      default:
        return c.lastContent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('消息'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(rootNavigatorKey.currentContext!)
              .maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: '聊天设置',
            onPressed: () => Navigator.of(rootNavigatorKey.currentContext!).push(
              MaterialPageRoute(builder: (_) => const ChatSettingsPage()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? const Center(
                  child: GeneralEmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: '还没有消息',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final c = _conversations[index];
                      final unread = SocialService.unreadOf(c);
                      return ListTile(
                        leading: ClipOval(
                          child: NetworkImgLayer(
                            width: 48,
                            height: 48,
                            src: SocialService.proxiedAvatar(c.avatar),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(c.nickname,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (c.lastTime > 0)
                              Text(
                                _timeText(c.lastTime),
                                style: TextStyle(
                                    fontSize: 11, color: colorScheme.outline),
                              ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _preview(c),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$unread',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white),
                                ),
                              ),
                            ],
                          ],
                        ),
                        onTap: () => _openChat(c),
                      );
                    },
                  ),
                ),
    );
  }
}

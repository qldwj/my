import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';

/// 好友聊天页（文本 / 小表情 / 分享动漫 / 分享规则）
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.friend});

  final SocialProfile friend;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<SocialChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _showEmoji = false;
  String? _myUid;

  static const List<String> _emojis = [
    '😀', '😂', '😊', '😍', '🥰', '😎', '🤔', '😭',
    '😅', '😤', '🥳', '😴', '👍', '👎', '👏', '🙏',
    '💪', '🔥', '❤️', '💔', '✨', '🎉', '🍚', '🥤',
    '📺', '🎬', '🍜', '🐱', '🐶', '🌸',
  ];

  @override
  void initState() {
    super.initState();
    _myUid = SocialService.restoreLocalProfile()?.uid;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final messages = await SocialService.chatHistory(widget.friend.uid);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(messages);
      _loading = false;
    });
    _scrollToBottom(animate: false);
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: animate
              ? const Duration(milliseconds: 250)
              : Duration.zero,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text, {String type = 'text'}) async {
    final content = text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await SocialService.sendMessage(
      toUid: widget.friend.uid,
      type: type,
      content: content,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (error == null) {
      _input.clear();
      await _loadHistory();
    } else {
      KazumiDialog.showToast(message: '❌ $error');
    }
  }

  String _timeText(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return hm;
    }
    return '${dt.month}/${dt.day} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.friend.avatar.isNotEmpty)
              ClipOval(
                child: NetworkImgLayer(
                    width: 28,
                    height: 28,
                    src: SocialService.proxiedAvatar(widget.friend.avatar)),
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(widget.friend.nickname,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text('还没有消息，打个招呼吧 👋'),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final m = _messages[index];
                          final isMe = m.fromUid == _myUid;
                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.sizeOf(context).width * 0.7),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? colorScheme.primary
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: Radius.circular(
                                      isMe ? 14 : 4),
                                  bottomRight: Radius.circular(
                                      isMe ? 4 : 14),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _buildMessageContent(m, isMe),
                                  const SizedBox(height: 2),
                                  Text(
                                    _timeText(m.createdAt),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMe
                                          ? colorScheme.onPrimary
                                              .withValues(alpha: 0.7)
                                          : colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_showEmoji)
            SizedBox(
              height: 180,
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: _emojis.length,
                itemBuilder: (context, index) => InkWell(
                  onTap: () => _send(_emojis[index], type: 'emoji'),
                  child: Center(
                      child: Text(_emojis[index],
                          style: const TextStyle(fontSize: 26))),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '表情',
                    icon: Icon(
                      _showEmoji
                          ? Icons.keyboard_alt_rounded
                          : Icons.emoji_emotions_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _showEmoji = !_showEmoji),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: '发消息…',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                      onSubmitted: (v) => _send(v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(_input.text),
                    icon: const Icon(Icons.send_rounded),
                    tooltip: '发送',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 消息内容（text/emoji/anime/rule 不同渲染）
  Widget _buildMessageContent(SocialChatMessage m, bool isMe) {
    final color = isMe ? Colors.white : null;
    switch (m.type) {
      case 'emoji':
        return Text(m.content, style: const TextStyle(fontSize: 32));
      case 'anime':
        return InkWell(
          onTap: () => Clipboard.setData(ClipboardData(text: m.content)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isMe ? Colors.white : Colors.black)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.movie_rounded, size: 18, color: color),
                const SizedBox(height: 2),
                Text('分享的番剧\n${m.content}',
                    style: TextStyle(fontSize: 13, color: color)),
              ],
            ),
          ),
        );
      case 'rule':
        return InkWell(
          onTap: () => Clipboard.setData(ClipboardData(text: m.content)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isMe ? Colors.white : Colors.black)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.extension_rounded, size: 18, color: color),
                const SizedBox(height: 2),
                Text('分享的规则\n${m.content}',
                    style: TextStyle(fontSize: 13, color: color)),
              ],
            ),
          ),
        );
      default:
        return Text(m.content, style: TextStyle(fontSize: 15, color: color));
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/online_dot.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/animeko_converter.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/utils/encoding.dart';

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
  final PluginsController pluginsController = inject<PluginsController>();
  Timer? _timer;

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
    // 🆕 轮询新消息（每 5 秒）
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadHistory(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory({bool silent = false}) async {
    final messages = await SocialService.chatHistory(widget.friend.uid);
    if (!mounted) return;
    // 🔧 拉取失败（返回空）但本地已有消息时保留旧列表，避免历史"消失"
    if (messages.isEmpty && _messages.isNotEmpty) return;
    setState(() {
      final hadNew = messages.isNotEmpty &&
          (_messages.isEmpty ||
              messages.last.id > _messages.last.id);
      _messages
        ..clear()
        ..addAll(messages);
      _loading = false;
      if (hadNew && !silent) {
        _scrollToBottom(animate: true);
      }
    });
    // 🆕 标记已读：记录当前最大消息 id
    if (messages.isNotEmpty) {
      await SocialService.markRead(widget.friend.uid, messages.last.id);
    }
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

  /// 🆕 "+"菜单：分享收藏的番剧 / 分享规则
  Future<void> _showPlusMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.movie_filter_outlined),
              title: const Text('分享番剧'),
              subtitle: const Text('从你的收藏里选一部发给好友'),
              onTap: () => Navigator.pop(ctx, 'anime'),
            ),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('分享规则'),
              subtitle: const Text('从你的规则列表里选一条发给好友'),
              onTap: () => Navigator.pop(ctx, 'rule'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'anime') {
      await _pickAnime();
    } else if (choice == 'rule') {
      await _pickRule();
    }
  }

  /// 从收藏里选番剧 → 发 anime 消息
  Future<void> _pickAnime() async {
    final collectibles = GStorage.collectibles.values.toList()
      ..sort((a, b) =>
          b.time.millisecondsSinceEpoch.compareTo(a.time.millisecondsSinceEpoch));
    if (collectibles.isEmpty) {
      KazumiDialog.showToast(message: '收藏里还没有番剧');
      return;
    }
    final picked = await showModalBottomSheet<CollectedBangumi>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择要分享的番剧',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: collectibles.length,
                itemBuilder: (context, index) {
                  final c = collectibles[index];
                  final item = c.bangumiItem;
                  final name =
                      item.nameCn.isNotEmpty ? item.nameCn : item.name;
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: NetworkImgLayer(
                          width: 44,
                          height: 60,
                          src: item.images['large'] ?? ''),
                    ),
                    title: Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('ID: ${item.id}'),
                    onTap: () => Navigator.pop(ctx, c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final item = picked.bangumiItem;
    final name = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    // 🆕 番剧分享：内容为 JSON（含 id/名称/封面/评分），渲染成可点击的封面卡片
    final content = json.encode({
      'id': item.id,
      'name': name,
      'cover': item.images['large'] ?? '',
      'rating': item.ratingScore,
    });
    final error = await SocialService.sendMessage(
      toUid: widget.friend.uid,
      type: 'anime',
      content: content,
    );
    if (!mounted) return;
    if (error == null) {
      await _loadHistory();
    } else {
      KazumiDialog.showToast(message: '❌ $error');
    }
  }

  /// 从规则列表里选规则 → 发 rule 消息
  Future<void> _pickRule() async {
    final plugins = pluginsController.pluginList.toList();
    if (plugins.isEmpty) {
      KazumiDialog.showToast(message: '还没有规则');
      return;
    }
    final picked = await showModalBottomSheet<Plugin>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择要分享的规则',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: plugins.length,
                itemBuilder: (context, index) {
                  final p = plugins[index];
                  return ListTile(
                    leading: const Icon(Icons.extension_rounded),
                    title: Text(p.name, maxLines: 1),
                    subtitle: Text(p.version.isNotEmpty ? 'v${p.version}' : ''),
                    onTap: () => Navigator.pop(ctx, p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final pluginJson = json.encode(picked.toJson());
    final yhdmgzLink = jsonToKazumiBase64(pluginJson);
    final content = '🧩 ${picked.name}\n$yhdmgzLink';
    final error = await SocialService.sendMessage(
      toUid: widget.friend.uid,
      type: 'rule',
      content: content,
    );
    if (!mounted) return;
    if (error == null) {
      await _loadHistory();
    } else {
      KazumiDialog.showToast(message: '❌ $error');
    }
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
            const SizedBox(width: 4),
            // 🆕 在线状态小圆点
            OnlineDot(online: widget.friend.isOnline, size: 10),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final navContext = rootNavigatorKey.currentContext;
            if (navContext == null || !navContext.mounted) return;
            Navigator.of(navContext).maybePop();
          },
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
                    tooltip: '分享番剧/规则',
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: _showPlusMenu,
                  ),
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
        return _buildAnimeMessage(m, isMe);
      case 'rule':
        return InkWell(
          onTap: () => _importRuleFromMessage(m.content),
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
                Text('分享的规则\n点击导入',
                    style: TextStyle(fontSize: 13, color: color)),
              ],
            ),
          ),
        );
      case 'sync':
        return _buildSyncInvite(m);
      default:
        return Text(m.content, style: TextStyle(fontSize: 15, color: color));
    }
  }

  /// 🆕 "一起看"邀请卡片：点击加入同步房间
  Widget _buildSyncInvite(SocialChatMessage m) {
    try {
      final data = json.decode(m.content);
      if (data is Map) {
        final name = data['name']?.toString() ?? '番剧';
        final episode = (data['episode'] as num?)?.toInt() ?? 0;
        final cover = data['cover']?.toString() ?? '';
        return InkWell(
          onTap: () => _acceptSyncInvite(Map<String, dynamic>.from(data)),
          child: Container(
            width: 230,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (cover.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: NetworkImgLayer(
                        width: 40, height: 56, src: cover),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🎬 邀请一起看',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        '《$name》${episode > 0 ? '第$episode集' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      const Text('点击加入房间',
                          style: TextStyle(
                              fontSize: 11, color: Colors.blueAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (_) {}
    return Text('🎬 邀请一起看',
        style: const TextStyle(fontSize: 13, color: Colors.blue));
  }

  /// 接受"一起看"邀请：打开详情页，播放后自动加入 Syncplay 房间
  Future<void> _acceptSyncInvite(Map<String, dynamic> data) async {
    final id = (data['id'] as num?)?.toInt() ?? 0;
    final episode = (data['episode'] as num?)?.toInt() ?? 1;
    final room = data['room']?.toString() ?? '';
    final endpoint = data['endpoint']?.toString() ?? '';
    if (id <= 0 || room.isEmpty) {
      KazumiDialog.showToast(message: '邀请信息无效');
      return;
    }
    // 记录待加入房间（播放页打开后自动加入）
    VideoPageController.pendingSyncInvite = (
      id: id,
      episode: episode,
      room: room,
      endpoint: endpoint,
      username: _genSyncUsername(),
    );
    // 打开番剧详情页，用户选源播放后自动加入房间（非阻塞加载）
    try {
      final item = await BangumiApi.getBangumiInfoByID(id);
      if (item == null || !mounted) {
        KazumiDialog.showToast(message: '番剧加载失败，请检查网络');
        return;
      }
      final navContext = rootNavigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;
      // 🔧 用 Modular 路由打开详情页
      navContext.pushNamed('/info/', arguments: item);
    } catch (e) {
      if (mounted) KazumiDialog.showToast(message: '加载失败：$e');
    }
  }

  /// 🆕 点击规则消息：解析 yhdmgz 链接 → 直接导入规则（不再只是复制）
  Future<void> _importRuleFromMessage(String content) async {
    try {
      // 提取消息里的 yhdmgz/kazumi/http 规则链接
      final match = RegExp(
        r'(yhdmgz://|kazumi://|https?://[^\s\n]+share\?gz=)[^\s\n]+',
      ).firstMatch(content);
      if (match == null) {
        KazumiDialog.showToast(message: '消息里没有可导入的规则链接');
        return;
      }
      final url = match.group(0)!;
      final jsonStr = kazumiBase64ToJson(url);
      final data = jsonDecode(jsonStr);
      int count = 0;
      if (data is Map &&
          data.containsKey('name') &&
          data.containsKey('searchURL')) {
        // 单个 Kazumi 规则
        await pluginsController
            .updatePlugin(Plugin.fromJson(Map<String, dynamic>.from(data)));
        count = 1;
      } else if (data is Map || data is List) {
        // Animeko 批量格式
        final plugins = AnimekoRuleConverter.convertFromJson(jsonEncode(data));
        for (final plugin in plugins) {
          await pluginsController.updatePlugin(plugin);
          count++;
        }
      }
      if (!mounted) return;
      if (count > 0) {
        KazumiDialog.showToast(message: '✅ 成功导入 $count 条规则');
      } else {
        KazumiDialog.showToast(message: '未找到可导入的规则');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '规则导入失败：$e');
    }
  }

  /// 生成 Syncplay 用户名（6~10 位随机小写字母）
  String _genSyncUsername() {
    const chars = 'abcdefghijklmnopqrstuvwxyz';
    final r = Random();
    final len = 6 + r.nextInt(5);
    final buf = StringBuffer();
    for (var i = 0; i < len; i++) {
      buf.write(chars[r.nextInt(chars.length)]);
    }
    return buf.toString();
  }

  /// 🆕 番剧消息：解析 JSON → 封面卡片，点击直接打开详情页
  Widget _buildAnimeMessage(SocialChatMessage m, bool isMe) {
    // 尝试解析 JSON 卡片（新格式）
    try {
      final data = json.decode(m.content);
      if (data is Map) {
        final id = (data['id'] as num?)?.toInt() ?? 0;
        final name = data['name']?.toString() ?? '番剧';
        final cover = data['cover']?.toString() ?? '';
        final rating = (data['rating'] as num?)?.toDouble() ?? 0;
        if (id > 0) {
          return _AnimeShareCard(
            id: id,
            name: name,
            cover: cover,
            rating: rating,
            onTap: () => _openAnimeDetail(id),
          );
        }
      }
    } catch (_) {}
    // 旧格式（纯文本）：点击复制
    return InkWell(
      onTap: () => Clipboard.setData(ClipboardData(text: m.content)),
      child: Text('🎬 ${m.content}', style: TextStyle(fontSize: 13)),
    );
  }

  /// 打开番剧详情页（非阻塞加载，失败提示，不卡"加载中"）
  Future<void> _openAnimeDetail(int id) async {
    try {
      final item = await BangumiApi.getBangumiInfoByID(id);
      if (item == null || !mounted) {
        KazumiLogger().w('OpenAnime: getBangumiInfoByID 返回 null, id=$id');
        KazumiDialog.showToast(message: '番剧加载失败，请检查网络');
        return;
      }
      final navContext = rootNavigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) {
        KazumiLogger().w('OpenAnime: rootNavigatorKey.context 为空');
        return;
      }
      try {
        // 🔧 用 Modular 路由（与详情页分享一致），避免 Navigator.of 路由不匹配
        await navContext.pushNamed('/info/', arguments: item);
      } catch (e, st) {
        // 跳转本身失败（如路由异常），不影响
        KazumiLogger().e('OpenAnime: pushNamed 失败', error: e, stackTrace: st);
      }
    } catch (e, st) {
      KazumiLogger().e(
          'OpenAnime: 打开详情失败 id=$id', error: e, stackTrace: st);
      if (mounted) KazumiDialog.showToast(message: '打开详情失败：$e');
    }
  }
}

/// 🆕 番剧分享卡片（封面 + 名称 + 评分，点击直达详情页）
class _AnimeShareCard extends StatelessWidget {
  const _AnimeShareCard({
    required this.id,
    required this.name,
    required this.cover,
    required this.rating,
    required this.onTap,
  });

  final int id;
  final String name;
  final String cover;
  final double rating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 220,
          child: Row(
            children: [
              // 封面
              SizedBox(
                width: 72,
                height: 96,
                child: cover.isNotEmpty
                    ? NetworkImgLayer(
                        width: 72,
                        height: 96,
                        src: SocialService.proxiedAvatar(cover),
                      )
                    : Container(
                        color: colorScheme.primaryContainer,
                        child: Icon(Icons.movie_outlined,
                            color: colorScheme.onPrimaryContainer),
                      ),
              ),
              const SizedBox(width: 10),
              // 信息
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      if (rating > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 15, color: Colors.amber),
                            const SizedBox(width: 3),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '点击查看详情',
                        style: TextStyle(
                            fontSize: 11, color: colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

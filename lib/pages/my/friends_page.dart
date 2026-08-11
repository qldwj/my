import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/pages/my/chat_page.dart';
import 'package:kazumi/services/social/social_service.dart';

/// 我的好友页
///
/// - 顶部搜索：按 uid / 昵称搜索用户 → 添加好友
/// - 好友列表：点击进入聊天
/// - 右上角：好友申请列表（同意/拒绝）
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final TextEditingController _searchController = TextEditingController();

  List<SocialProfile> _friends = [];
  List<SocialProfile> _searchResults = [];
  bool _loadingFriends = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() => _loadingFriends = true);
    final friends = await SocialService.friendList();
    if (!mounted) return;
    setState(() {
      _friends = friends;
      _loadingFriends = false;
    });
  }

  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty || _searching) return;
    setState(() => _searching = true);
    final results = await SocialService.searchUsers(keyword);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
    if (results.isEmpty) {
      KazumiDialog.showToast(message: '没有找到相关用户');
    }
  }

  Future<void> _addFriend(SocialProfile user) async {
    final error = await SocialService.addFriend(user.uid);
    if (!mounted) return;
    KazumiDialog.showToast(
        message: error == null ? '✅ 好友申请已发送' : '❌ $error');
  }

  Future<void> _openRequests() async {
    final requests = await SocialService.friendRequests();
    if (!mounted) return;
    showModalBottomSheet<void>(
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
              child: Text('好友申请',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: requests.isEmpty
                  ? const Center(child: Text('暂无好友申请'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: requests.length,
                      itemBuilder: (context, index) {
                        final r = requests[index];
                        return ListTile(
                          leading: _Avatar(profile: r, size: 44),
                          title: Text(r.nickname),
                          subtitle: Text('uid: ${r.uid}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle,
                                    color: Colors.green),
                                onPressed: () async {
                                  await SocialService.handleFriendRequest(
                                      r.uid,
                                      accept: true);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _loadFriends();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel,
                                    color: Colors.grey),
                                onPressed: () async {
                                  await SocialService.handleFriendRequest(
                                      r.uid,
                                      accept: false);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat(SocialProfile friend) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatPage(friend: friend)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('我的好友'),
        actions: [
          IconButton(
            tooltip: '好友申请',
            onPressed: _openRequests,
            icon: const Icon(Icons.person_add_alt_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索 uid 或昵称',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _searching ? null : _search,
                  icon: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search_rounded),
                ),
              ],
            ),
          ),
          // 搜索结果
          if (_searchResults.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Text('搜索结果',
                      style: TextStyle(
                          fontSize: 13, color: colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _searchResults = []),
                    child: const Text('清除'),
                  ),
                ],
              ),
            ),
            ..._searchResults.map((u) => ListTile(
                  leading: _Avatar(profile: u, size: 44),
                  title: Text(u.nickname),
                  subtitle: Text('uid: ${u.uid}'),
                  trailing: FilledButton.tonal(
                    onPressed: () => _addFriend(u),
                    child: const Text('添加'),
                  ),
                )),
            const Divider(height: 16),
          ],
          // 好友列表
          Expanded(
            child: _loadingFriends
                ? const Center(child: CircularProgressIndicator())
                : _friends.isEmpty
                    ? const Center(
                        child: GeneralEmptyState(
                          icon: Icons.people_outline_rounded,
                          title: '还没有好友',
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _friends.length,
                        itemBuilder: (context, index) {
                          final f = _friends[index];
                          return ListTile(
                            leading: _Avatar(profile: f, size: 48),
                            title: Text(f.nickname,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text('uid: ${f.uid}'),
                            trailing: const Icon(Icons.chat_bubble_outline),
                            onTap: () => _openChat(f),
                            onLongPress: () async {
                              final confirm = await KazumiDialog.show<bool>(
                                builder: (ctx) => AlertDialog(
                                  title: Text('删除好友「${f.nickname}」？'),
                                  content: const Text('删除后无法查看聊天记录'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          KazumiDialog.dismiss(popWith: false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      onPressed: () =>
                                          KazumiDialog.dismiss(popWith: true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await SocialService.removeFriend(f.uid);
                                _loadFriends();
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// 头像组件（无头像显示占位）
class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile, required this.size});

  final SocialProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (profile.avatar.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: colorScheme.primaryContainer,
        child: Icon(Icons.person_rounded,
            color: colorScheme.onPrimaryContainer, size: size * 0.6),
      );
    }
    return ClipOval(
      child: NetworkImgLayer(
        width: size,
        height: size,
        src: SocialService.proxiedAvatar(profile.avatar),
      ),
    );
  }
}

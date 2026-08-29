import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/online_dot.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/auth_service.dart';

/// 个人主页（查看他人主页）
///
/// 从评论/吐槽/好友列表点击头像进入。
/// 受对方隐私设置约束，可能显示遮挡信息。
class ProfilePage extends StatefulWidget {
  final String uid;
  final String? nickname;
  final String? avatar;

  const ProfilePage({
    super.key,
    required this.uid,
    this.nickname,
    this.avatar,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  SocialProfile? _profile;
  bool _isFriend = false;
  bool _loading = true;
  bool _addingFriend = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await SocialService.getPublicProfile(widget.uid);
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _error = '用户不存在';
          _loading = false;
        });
        return;
      }
      setState(() {
        _profile = res;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '加载失败'; _loading = false; });
    }
  }

  Future<void> _addFriend() async {
    if (!AuthService.isLoggedIn) {
      KazumiDialog.showToast(message: '请先登录');
      return;
    }
    setState(() => _addingFriend = true);
    final err = await SocialService.addFriend(widget.uid);
    if (!mounted) return;
    setState(() => _addingFriend = false);
    if (err != null) {
      KazumiDialog.showToast(message: err);
    } else {
      KazumiDialog.showToast(message: '好友申请已发送');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('个人主页')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(fontSize: 16)))
              : _profile == null
                  ? const Center(child: Text('用户不存在'))
                  : _buildContent(cs),
      floatingActionButton: _profile != null && !_profile!.privacy && !_isFriend
          ? FloatingActionButton.extended(
              onPressed: _addingFriend ? null : _addFriend,
              icon: _addingFriend
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.person_add),
              label: Text(_addingFriend ? '发送中...' : '加好友'),
            )
          : null,
    );
  }

  Widget _buildContent(ColorScheme cs) {
    final p = _profile!;

    // 隐私保护：无法查看主页
    if (p.privacy) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundImage: p.avatar.isNotEmpty
                    ? NetworkImage(SocialService.proxiedAvatar(p.avatar))
                    : null,
                child: p.avatar.isEmpty ? const Icon(Icons.person, size: 48) : null,
              ),
              const SizedBox(height: 16),
              Text(p.nickname, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('该用户设置了隐私保护，无法查看主页',
                      style: TextStyle(color: Colors.orange, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 正常显示
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 头像 + 昵称
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 56,
                backgroundImage: p.avatar.isNotEmpty
                    ? NetworkImage(SocialService.proxiedAvatar(p.avatar))
                    : null,
                child: p.avatar.isEmpty ? const Icon(Icons.person, size: 56) : null,
              ),
              const SizedBox(height: 12),
              Text(p.nickname, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OnlineDot(isOnline: p.isOnlineNow, size: 10),
                  const SizedBox(width: 6),
                  Text(p.isOnlineNow ? '在线' : '离线',
                    style: TextStyle(fontSize: 13, color: cs.outline)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 个人介绍
        if (p.bio.isNotEmpty) ...[
          _buildInfoCard(cs, '个人介绍', p.bio),
          const SizedBox(height: 12),
        ],

        // 资料卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('基本资料', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
                const Divider(),
                _buildInfoRow('UID', p.uid),
                const SizedBox(height: 8),
                _buildInfoRow('性别', p.genderText),
                const SizedBox(height: 8),
                _buildInfoRow('生日', p.birthday.isNotEmpty ? p.birthday : '未填写'),
                const SizedBox(height: 8),
                _buildInfoRow('注册时间', p.createdAt > 0
                    ? DateTime.fromMillisecondsSinceEpoch(p.createdAt * 1000).toLocal().toString().split(' ')[0]
                    : '未知'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(ColorScheme cs, String title, String content) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(content, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.outline)),
        Text(value, style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}
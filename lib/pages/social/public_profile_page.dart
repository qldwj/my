import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/friend_service.dart';

/// 🆕 公开个人主页（分享链接 api/u/{uid} 打开；可一键加好友/关注）
class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({super.key, required this.uid});

  final int uid;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  bool _loading = true;
  Map<String, dynamic>? _profile;
  bool _following = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final p = await FriendService.fetchProfile(widget.uid);
    if (!mounted) return;
    if (p == null) {
      setState(() {
        _loading = false;
        _error = '用户不存在或加载失败';
      });
      return;
    }
    setState(() {
      _profile = p;
      _following = p['followedByMe'] == true;
      _loading = false;
    });
  }

  Future<void> _toggleFollow() async {
    if (_busy) return;
    final token = AuthService.getLocalToken();
    if (token == null) {
      KazumiDialog.showToast(message: '请先登录');
      return;
    }
    setState(() => _busy = true);
    final res = _following
        ? await FriendService.unfollow(widget.uid)
        : await FriendService.follow(widget.uid);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['error'] != null) {
      KazumiDialog.showToast(message: '操作失败：${res['error']}');
      return;
    }
    setState(() => _following = res['following'] == true);
    KazumiDialog.showToast(message: _following ? '已关注 ✅' : '已取消关注');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('个人主页')),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_rounded, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final p = _profile!;
    final avatar = p['avatar']?.toString() ?? '';
    final nickname = p['nickname']?.toString() ?? '用户${widget.uid}';
    final reg = p['registered'] is int && (p['registered'] as int) > 0
        ? _fmtDate(p['registered'] as int)
        : '未知';
    final collected = p['collectedCount'];
    final self = AuthService.getLocalToken() != null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 头像 + 昵称
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: avatar.isEmpty
                    ? Container(
                        color: cs.primaryContainer,
                        child: Icon(Icons.person_rounded,
                            size: 40, color: cs.onPrimaryContainer),
                      )
                    : Image.network(avatar,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            color: cs.primaryContainer,
                            child: Icon(Icons.person_rounded,
                                size: 40, color: cs.onPrimaryContainer))),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nickname,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Text('UID ${widget.uid} · 注册于 $reg',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text('积分 ${p['coins'] ?? 0}',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // 统计
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _stat(cs, collected?.toString() ?? '-', '收藏'),
              _divider(cs),
              _stat(cs, '${p['followerCount'] ?? 0}', '粉丝'),
              _divider(cs),
              _stat(cs, '${p['followingCount'] ?? 0}', '关注'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 关注按钮
        if (self)
          FilledButton.icon(
            onPressed: _busy ? null : _toggleFollow,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: Icon(_following
                ? Icons.person_remove_rounded
                : Icons.person_add_alt_1_rounded),
            label: Text(_busy
                ? '处理中…'
                : (_following ? '已关注 · 取消' : '加为好友 / 关注')),
          )
        else
          OutlinedButton.icon(
            onPressed: () => KazumiDialog.showToast(message: '请先登录后再关注'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('登录后可关注 TA'),
          ),
        const SizedBox(height: 12),
        Text(
          '通过分享链接打开即可查看 TA 的追番主页，关注后可在好友动态里看到 TA 在看什么。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _stat(ColorScheme cs, String v, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(v,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme cs) {
    return Container(width: 1, height: 32, color: cs.outlineVariant);
  }

  String _fmtDate(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/my/bangumi_login_page.dart';
import 'package:kazumi/pages/my/kazumi_login_page.dart';
import 'package:kazumi/pages/my/qrcode_login_page.dart';
import 'package:kazumi/pages/my/friends_page.dart';
import 'package:kazumi/pages/my/my_space_view.dart';
import 'package:kazumi/pages/my/privacy_settings_page.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 我的页 —— 重新设计，与官方 2.3.1 风格对齐
///
/// 结构：AppBar(隐私 + 二维码 + 设置) → MySpaceView
class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  SocialProfile? _socialProfile;
  int _friendRequestCount = 0;
  int _chatUnreadCount = 0;
  String _bangumiAvatarUrl = '';
  String _bangumiName = '';
  int weeklyGoal = 0;
  int thisWeekEpisodes = 0;

  @override
  void initState() {
    super.initState();
    _loadGoal();
    _loadBangumiUser();
    _loadSocialProfile();
  }

  // ── 数据加载 ──

  void _loadGoal() {
    weeklyGoal = GStorage.getSetting<int>(SettingsKeys.weeklyWatchGoal);
    thisWeekEpisodes = _countThisWeekEpisodes();
  }

  int _countThisWeekEpisodes() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: now.weekday - 1));
    var count = 0;
    try {
      for (final h in HistoryRepository().getAllHistories()) {
        for (final p in h.progresses.values) {
          final t = p.effectiveUpdatedAtMs(h.lastWatchTime);
          if (t >= weekStart.millisecondsSinceEpoch) count++;
        }
      }
    } catch (_) {}
    return count;
  }

  void _onWeeklyGoalChanged(int newGoal) {
    setState(() => weeklyGoal = newGoal);
    GStorage.putSetting(SettingsKeys.weeklyWatchGoal, newGoal);
  }

  Future<void> _loadSocialProfile() async {
    if (!AuthService.isLoggedIn) return;
    SocialService.restoreLocalProfile();
    final profile = await SocialService.getProfile();
    if (profile != null && mounted) {
      setState(() => _socialProfile = profile);
    }
    final status = await SocialService.deleteStatus();
    if (status?.pending == true) {
      await SocialService.cancelDelete();
    }
    final requests = await SocialService.friendRequests();
    final unread = await SocialService.totalUnread();
    if (mounted) {
      setState(() {
        _friendRequestCount = requests.length;
        _chatUnreadCount = unread;
      });
    }
  }

  Future<void> _loadBangumiUser() async {
    if (GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isEmpty) {
      return;
    }
    try {
      final user = await BangumiApi.getCurrentUser();
      if (user != null && mounted) {
        setState(() {
          _bangumiAvatarUrl = user.avatar.large;
          _bangumiName =
              user.nickname.isNotEmpty ? user.nickname : user.username;
        });
      }
    } catch (_) {}
  }

  // ── 导航回调 ──

  void _open(MyDestination destination) {
    context.pushNamed(switch (destination) {
      MyDestination.theme => '/settings/theme',
      MyDestination.player => '/settings/player',
      MyDestination.danmaku => '/settings/danmaku/',
      MyDestination.rules => '/settings/plugin/',
      MyDestination.history => '/settings/history/',
      MyDestination.downloads => '/settings/download/',
      MyDestination.sync => '/settings/sync',
      MyDestination.storage => '/settings/storage',
      MyDestination.about => '/settings/about/',
    });
  }

  void _openLogin() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text('选择登录方式',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.brightness_6_rounded),
              title: const Text('Bangumi 一键登录'),
              subtitle: const Text('同步收藏与进度'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const BangumiLoginPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key_rounded),
              title: const Text('樱花动漫账号登录'),
              subtitle: const Text('社交 / 同步 / 好友'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const KazumiLoginPage()),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _openFriends() {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录樱花动漫账号')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FriendsPage(),
      ),
    ).then((_) => _loadSocialProfile());
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text(
          '我的',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        needTopOffset: false,
        actions: [
          if (AuthService.isLoggedIn)
            IconButton(
              tooltip: '隐私设置',
              icon: const Icon(Icons.privacy_tip_outlined, size: 22),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const PrivacySettingsPage()),
                );
              },
            ),
          if (AuthService.isLoggedIn)
            IconButton(
              tooltip: '显示登录二维码',
              icon: const Icon(Icons.qr_code_2_rounded, size: 22),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QrcodeLoginPage()),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MySettingsButton(
              onTap: () => context.pushNamed('/settings/'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: MySpaceView(
          onOpen: _open,
          onLogin: _openLogin,
          onFriends: _openFriends,
          socialProfile: _socialProfile,
          friendRequestCount: _friendRequestCount,
          chatUnreadCount: _chatUnreadCount,
          bangumiAvatarUrl: _bangumiAvatarUrl,
          bangumiName: _bangumiName,
          weeklyGoal: weeklyGoal,
          thisWeekEpisodes: thisWeekEpisodes,
          onWeeklyGoalChanged: _onWeeklyGoalChanged,
        ),
      ),
    );
  }
}

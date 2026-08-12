import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/bangumi_history_card.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/settings_section_card.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/my/bangumi_login_page.dart';
import 'package:kazumi/pages/my/kazumi_login_page.dart';
import 'package:kazumi/pages/my/qrcode_login_page.dart';
import 'package:kazumi/pages/my/friends_page.dart';
import 'package:kazumi/pages/my/chat_list_page.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/kazumi_sync_service.dart';
import 'package:path_provider/path_provider.dart';

/// 我的页
///
/// 结构（从上到下）：
/// 1. 账号：两个登录（Bangumi 一键登录 + 樱花动漫账号）
/// 2. 历史记录 + 离线下载（仅这两个选项）
/// 3. 设置（入口，进入总设置页）
/// 4. 简易历史记录（最多 5 条，点击直接继续观看）
class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  List<History> _recentHistories = [];
  bool _syncingCloud = false;
  int weeklyGoal = 0;
  int thisWeekEpisodes = 0;
  String _bangumiAvatarUrl = '';
  String _bangumiName = '';
  SocialProfile? _socialProfile;
  int _friendRequestCount = 0;
  int _chatUnreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadRecentHistories();
    _loadGoal();
    _loadBangumiUser();
    _loadSocialProfile();
  }

  /// 加载樱花动漫社交资料（uid/昵称/头像），并取消未完成的账号销毁
  Future<void> _loadSocialProfile() async {
    if (!AuthService.isLoggedIn) return;
    SocialService.restoreLocalProfile();
    final profile = await SocialService.getProfile();
    if (profile != null && mounted) {
      setState(() => _socialProfile = profile);
    }
    // 🆕 登录即取消销毁（7 天冷静期规则）
    final status = await SocialService.deleteStatus();
    if (status?.pending == true) {
      await SocialService.cancelDelete();
    }
    // 🆕 红点：好友申请数 + 消息未读数
    final requests = await SocialService.friendRequests();
    final unread = await SocialService.totalUnread();
    if (mounted) {
      setState(() {
        _friendRequestCount = requests.length;
        _chatUnreadCount = unread;
      });
    }
  }

  /// 已登录 Bangumi 时拉取头像/昵称（走 api.qlyyz.top 镜像）
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

  void _loadGoal() {
    weeklyGoal = GStorage.getSetting<int>(SettingsKeys.weeklyWatchGoal);
    thisWeekEpisodes = _countThisWeekEpisodes();
  }

  /// 统计本周（周一起）已看的集数
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

  void _loadRecentHistories() {
    try {
      final all = HistoryRepository().getAllHistories();
      all.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      _recentHistories = all.take(5).toList();
    } catch (e) {
      _recentHistories = [];
    }
  }

  /// 🆕 资料编辑：修改昵称 / 更换头像（头像保存到相册 DCIM 并上传）
  Future<void> _showProfileEditor(BuildContext context) async {
    final profile = _socialProfile;
    if (profile == null) return;
    final nicknameController = TextEditingController(text: profile.nickname);
    var currentAvatar = profile.avatar;
    var uploading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('个人资料',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: uploading
                      ? null
                      : () async {
                          final picked = await ImagePicker()
                              .pickImage(source: ImageSource.gallery);
                          if (picked == null) return;
                          final bytes = await picked.readAsBytes();
                          if (bytes.length > 2 * 1024 * 1024) {
                            KazumiDialog.showToast(message: '图片过大（最大 2MB）');
                            return;
                          }
                          // 🆕 头像不保存在本机，直接 base64 上传服务器
                          setSheetState(() => uploading = true);
                          final error = await SocialService.uploadAvatar(
                              base64Encode(bytes));
                          if (!ctx.mounted) return;
                          setSheetState(() => uploading = false);
                          if (error == null) {
                            currentAvatar =
                                SocialService.myProfile?.avatar ??
                                    currentAvatar;
                            setSheetState(() {});
                            if (mounted) {
                              setState(() =>
                                  _socialProfile = SocialService.myProfile);
                            }
                            KazumiDialog.showToast(message: '✅ 头像已更新');
                          } else {
                            KazumiDialog.showToast(message: '❌ $error');
                          }
                        },
                  child: Stack(
                    children: [
                      ClipOval(
                        child: currentAvatar.isNotEmpty
                            ? NetworkImgLayer(
                                width: 80,
                                height: 80,
                                src:
                                    SocialService.proxiedAvatar(currentAvatar),
                              )
                            : Container(
                                width: 80,
                                height: 80,
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .primaryContainer,
                                child: Icon(Icons.person_rounded,
                                    size: 48,
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onPrimaryContainer),
                              ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: uploading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.photo_camera_rounded,
                                  size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nicknameController,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '昵称',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final name = nicknameController.text.trim();
                        if (name.isEmpty || name == profile.nickname) {
                          Navigator.pop(ctx);
                          return;
                        }
                        final error = await SocialService.updateProfile(
                            nickname: name);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (error == null) {
                          if (mounted) {
                            setState(() =>
                                _socialProfile = SocialService.myProfile);
                          }
                          KazumiDialog.showToast(message: '✅ 昵称已更新');
                        } else {
                          KazumiDialog.showToast(message: '❌ $error');
                        }
                      },
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 缓存清理弹窗：显示图片缓存占用 + 一键清理（物理删除缓存目录，与关于页一致）
  Future<void> _showCacheCleanup(BuildContext context) async {
    final cacheSize = await _getCacheSize();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('缓存清理'),
        content: Text(
          '图片缓存占用：${_formatSize(cacheSize)}\n\n'
          '清理后，下次浏览图片会重新下载，'
          '不影响已下载的视频、收藏和历史记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: cacheSize == 0
                ? null
                : () async {
                    Navigator.pop(ctx);
                    // 🔧 物理删除缓存目录（emptyCache 只清内存标记，不会真正释放）
                    try {
                      final base = await getTemporaryDirectory();
                      final dir = Directory('${base.path}/libCachedImageData');
                      if (await dir.exists()) {
                        await dir.delete(recursive: true);
                      }
                    } catch (e) {
                      KazumiLogger().e('缓存清理失败', error: e);
                    }
                    if (mounted) {
                      KazumiDialog.showToast(message: '缓存已清理 ✅');
                    }
                  },
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
  }

  /// 云端同步（收藏 + 历史 + 播放进度）
  Future<void> _syncCloud(BuildContext context) async {
    if (!AuthService.isLoggedIn) {
      KazumiDialog.showToast(message: '请先登录樱花动漫账号');
      return;
    }
    if (_syncingCloud) return;
    _syncingCloud = true;
    try {
      KazumiDialog.show(
        clickMaskDismiss: false,
        builder: (context) => const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 16),
              Flexible(child: Text('正在云端同步…')),
            ],
          ),
        ),
      );
      final results = await KazumiSyncService.syncAll();
      if (!context.mounted) return;
      KazumiDialog.dismiss();
      KazumiDialog.show(
        builder: (context) => AlertDialog(
          title: const Text('同步结果'),
          content: Text(results.join('\n')),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: const Text('好的'),
            ),
          ],
        ),
      );
    } finally {
      _syncingCloud = false;
    }
  }

  /// 账号与数据管理：清除云端数据 / 注销账号
  Future<void> _manageAccountData(BuildContext context) async {
    if (!AuthService.isLoggedIn) {
      KazumiDialog.showToast(message: '请先登录樱花动漫账号');
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_off_rounded),
              title: const Text('清除云端数据'),
              subtitle: const Text('删除服务器上的收藏/历史/进度，保留账号'),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded,
                  color: Colors.red),
              title: const Text('注销账号',
                  style: TextStyle(color: Colors.red)),
              subtitle: const Text('删除账号和全部云端数据，不可恢复'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'clear') {
      final confirm = await KazumiDialog.show<bool>(
        builder: (context) => AlertDialog(
          title: const Text('清除云端数据'),
          content: const Text('将删除服务器上的收藏/历史/进度，本地数据保留。确定？'),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(popWith: false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => KazumiDialog.dismiss(popWith: true),
              child: const Text('清除'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      final res = await AuthService.clearData();
      if (!mounted) return;
      KazumiDialog.showToast(
        message: res['error'] != null ? '❌ ${res['error']}' : '✅ 云端数据已清除',
      );
    } else if (action == 'delete') {
      // 🆕 账号销毁：7 天冷静期，期间登录自动取消
      final confirm = await KazumiDialog.show<bool>(
        builder: (context) => AlertDialog(
          title: const Text('账号销毁', style: TextStyle(color: Colors.red)),
          content: const Text(
            '销毁账号后将删除账号和全部云端数据（收藏/历史/进度），不可恢复。\n\n'
            '有 7 天冷静期：期间再次登录即可取消销毁，7 天后账号自动删除。确定发起销毁？',
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(popWith: false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => KazumiDialog.dismiss(popWith: true),
              child: const Text('确认销毁'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      final error = await SocialService.requestDeleteAccount();
      AuthService.clearLocalToken();
      // 🔧 退出登录时清除社交资料缓存（避免切换账号残留）
      SocialService.clearProfileCache();
      if (!mounted) return;
      KazumiDialog.showToast(
        message: error != null
            ? '❌ $error'
            : '✅ 已发起账号销毁，7 天内登录可取消',
      );
    }
  }

  Future<int> _getCacheSize() async {
    try {
      // flutter_cache_manager 默认缓存目录：<临时目录>/libCachedImageData
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/libCachedImageData');
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bangumiLoggedIn =
        GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;

    return Scaffold(
      appBar: SysAppBar(
        title: const Text('我的'),
        needTopOffset: false,
        actions: [
          if (bangumiLoggedIn)
            IconButton(
              tooltip: '显示登录二维码',
              icon: const Icon(Icons.qr_code_2_rounded),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const QrcodeLoginPage(),
                  ),
                );
              },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── 账号（最上方两个登录）──
              SettingsSectionCard(
                title: '账号',
                children: [
                  SettingsEntryTile(
                    leading: bangumiLoggedIn
                        ? BangumiAvatar(url: _bangumiAvatarUrl, size: 40)
                        : Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.person_add,
                              color: Colors.blue,
                            ),
                          ),
                    title: bangumiLoggedIn
                        ? (_bangumiName.isNotEmpty
                            ? _bangumiName
                            : 'Bangumi 已登录')
                        : 'Bangumi 一键登录',
                    description:
                        bangumiLoggedIn ? '点击管理 Bangumi 账号' : '登录后可同步收藏与进度',
                    onTap: () {
                      final navContext = rootNavigatorKey.currentContext;
                      if (navContext == null || !navContext.mounted) return;
                      Navigator.of(navContext).push(
                        MaterialPageRoute(
                            builder: (_) => const BangumiLoginPage()),
                      );
                    },
                  ),
                  SettingsEntryTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AuthService.isLoggedIn
                            ? Colors.green.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: AuthService.isLoggedIn &&
                              _socialProfile != null &&
                              _socialProfile!.avatar.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: NetworkImgLayer(
                                width: 40,
                                height: 40,
                                src: SocialService.proxiedAvatar(
                                    _socialProfile!.avatar),
                              ),
                            )
                          : Icon(
                              AuthService.isLoggedIn
                                  ? Icons.check_circle
                                  : Icons.person_add,
                              color: AuthService.isLoggedIn
                                  ? Colors.green.shade600
                                  : Colors.blue.shade600,
                            ),
                    ),
                    title: AuthService.isLoggedIn
                        ? (_socialProfile?.nickname.isNotEmpty == true
                            ? _socialProfile!.nickname
                            : '樱花动漫账号已登录')
                        : '樱花动漫账号',
                    description: AuthService.isLoggedIn
                        ? (_socialProfile != null
                            ? 'uid: ${_socialProfile!.uid} · 管理账号 / 同步 / 绑定 Bangumi'
                            : '点击管理账号')
                        : '登录后可同步收藏与进度',
                    onTap: () {
                      final navContext = rootNavigatorKey.currentContext;
                      if (navContext == null || !navContext.mounted) return;
                      Navigator.of(navContext).push(
                        MaterialPageRoute(
                            builder: (_) => const KazumiLoginPage()),
                      );
                    },
                  ),
                  SettingsEntryTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AuthService.isLoggedIn
                            ? Colors.teal.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.people_rounded,
                        color: AuthService.isLoggedIn
                            ? Colors.teal.shade600
                            : Colors.grey.shade500,
                      ),
                    ),
                    title: '我的好友',
                    description: AuthService.isLoggedIn
                        ? '搜索好友 / 好友申请 / 聊天'
                        : '登录后可添加好友',
                    trailing: _friendRequestCount > 0
                        ? _Badge(count: _friendRequestCount, color: Colors.red)
                        : null,
                    onTap: () {
                      if (!AuthService.isLoggedIn) {
                        KazumiDialog.showToast(message: '请先登录樱花动漫账号');
                        return;
                      }
                      final navContext = rootNavigatorKey.currentContext;
                      if (navContext == null || !navContext.mounted) return;
                      Navigator.of(navContext).push(
                        MaterialPageRoute(
                            builder: (_) => const FriendsPage()),
                      ).then((_) => _loadSocialProfile());
                    },
                  ),
                  SettingsEntryTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AuthService.isLoggedIn
                            ? Colors.orange.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.card_giftcard_rounded,
                        color: AuthService.isLoggedIn
                            ? Colors.orange.shade600
                            : Colors.grey.shade500,
                      ),
                    ),
                    title: '邀请好友',
                    description: AuthService.isLoggedIn
                        ? (_socialProfile != null
                            ? '邀请码：${_socialProfile!.uid} · 点击复制邀请链接'
                            : '登录后获得邀请码')
                        : '登录后可邀请好友',
                    onTap: () {
                      if (!AuthService.isLoggedIn ||
                          _socialProfile == null) {
                        KazumiDialog.showToast(message: '请先登录樱花动漫账号');
                        return;
                      }
                      final link =
                          'https://qlyyz.xyz/invite?code=${_socialProfile!.uid}';
                      Clipboard.setData(ClipboardData(text: link));
                      KazumiDialog.showToast(
                          message: '✅ 邀请链接已复制，新用户注册双方得积分');
                    },
                  ),
                  SettingsEntryTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AuthService.isLoggedIn
                            ? Colors.indigo.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.chat_bubble_rounded,
                        color: AuthService.isLoggedIn
                            ? Colors.indigo.shade600
                            : Colors.grey.shade500,
                      ),
                    ),
                    title: '消息',
                    description: AuthService.isLoggedIn
                        ? '最近聊天 / 好友消息通知'
                        : '登录后可用',
                    trailing: _chatUnreadCount > 0
                        ? _Badge(count: _chatUnreadCount, color: Colors.red)
                        : null,
                    onTap: () {
                      if (!AuthService.isLoggedIn) {
                        KazumiDialog.showToast(message: '请先登录樱花动漫账号');
                        return;
                      }
                      final navContext = rootNavigatorKey.currentContext;
                      if (navContext == null || !navContext.mounted) return;
                      Navigator.of(navContext).push(
                        MaterialPageRoute(builder: (_) => const ChatListPage()),
                      ).then((_) => _loadSocialProfile());
                    },
                  ),
                  SettingsEntryTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AuthService.isLoggedIn
                            ? Colors.indigo.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.cloud_sync_rounded,
                        color: AuthService.isLoggedIn
                            ? Colors.indigo.shade600
                            : Colors.grey.shade500,
                      ),
                    ),
                    title: '云端同步',
                    description: AuthService.isLoggedIn
                        ? '同步收藏 / 历史 / 播放进度'
                        : '登录后可同步收藏与历史',
                    onTap: () => _syncCloud(context),
                  ),
                  SettingsEntryTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AuthService.isLoggedIn
                            ? Colors.red.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.security_rounded,
                        color: AuthService.isLoggedIn
                            ? Colors.red.shade400
                            : Colors.grey.shade500,
                      ),
                    ),
                    title: '账号与数据',
                    description: AuthService.isLoggedIn
                        ? '清除云端数据 / 注销账号'
                        : '登录后可管理账号数据',
                    onTap: () => _manageAccountData(context),
                  ),
                ],
              ),

              // ── 本周目标 ──
              SettingsSectionCard(
                title: '本周目标',
                leading: Icon(
                  Icons.flag_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                children: [
                  if (weeklyGoal <= 0)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            '本周还没设定目标，本周已看 $thisWeekEpisodes 集',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: () {
                              setState(() => weeklyGoal = 5);
                              GStorage.putSetting(
                                  SettingsKeys.weeklyWatchGoal, 5);
                            },
                            child: const Text('设定目标（5 集 / 周）'),
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '本周已看 $thisWeekEpisodes / $weeklyGoal 集',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: weeklyGoal > 1
                                    ? () {
                                        setState(() => weeklyGoal--);
                                        GStorage.putSetting(
                                            SettingsKeys.weeklyWatchGoal,
                                            weeklyGoal);
                                      }
                                    : null,
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setState(() => weeklyGoal++);
                                  GStorage.putSetting(SettingsKeys.weeklyWatchGoal,
                                      weeklyGoal);
                                },
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (thisWeekEpisodes / weeklyGoal).clamp(0.0, 1.0),
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            thisWeekEpisodes >= weeklyGoal
                                ? '🎉 本周目标已完成！'
                                : '还差 ${weeklyGoal - thisWeekEpisodes} 集达成目标',
                            style: TextStyle(
                              fontSize: 12,
                              color: thisWeekEpisodes >= weeklyGoal
                                  ? Colors.green
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              // ── 历史记录 + 离线下载（仅这两个选项）──
              SettingsSectionCard(
                children: [
                  SettingsEntryTile(
                    icon: Icons.history_rounded,
                    title: '历史记录',
                    description: '查看播放历史记录',
                    onTap: () => context.pushNamed('/settings/history/'),
                  ),
                  SettingsEntryTile(
                    icon: Icons.download_rounded,
                    title: '离线下载',
                    description: '查看和管理离线下载',
                    onTap: () => context.pushNamed('/settings/download/'),
                  ),
                  SettingsEntryTile(
                    icon: Icons.bar_chart_rounded,
                    title: '观看统计',
                    description: '查看你的追番报告和统计数据',
                    onTap: () => context.pushNamed('/stats/'),
                  ),
                  SettingsEntryTile(
                    icon: Icons.cleaning_services_rounded,
                    title: '缓存清理',
                    description: '查看图片缓存占用，一键清理释放空间',
                    onTap: () => _showCacheCleanup(context),
                  ),
                ],
              ),

              // ── 设置（入口）──
              SettingsSectionCard(
                children: [
                  SettingsEntryTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.settings_rounded,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: '设置',
                    description: '播放 / 下载 / 规则 / 同步等全部设置',
                    onTap: () => context.pushNamed('/settings'),
                  ),
                ],
              ),

              // ── 简易历史记录（最多 5 条，点击直接继续观看）──
              SettingsSectionCard(
                title: '历史记录',
                leading: Icon(
                  Icons.history_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                children: [
                  if (_recentHistories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无历史记录'),
                    )
                  else
                    for (final h in _recentHistories)
                      BangumiHistoryCardV(historyItem: h),
                  const Divider(height: 1),
                  ListTile(
                    onTap: () => context.pushNamed('/settings/history/'),
                    title: Text(
                      '更多历史记录请在历史记录页查看',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 🆕 红点角标（好友申请/消息未读）
class _Badge extends StatelessWidget {
  const _Badge({required this.count, this.color = Colors.red});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }
}

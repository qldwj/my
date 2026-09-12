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
import 'package:kazumi/pages/my/privacy_settings_page.dart';
import 'package:kazumi/pages/my/security_center_page.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
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
    // 首次进入检查是否已添加规则
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstTimeRule();
    });
  }

  /// 首次进入：未添加规则时提示
  void _checkFirstTimeRule() {
    try {
      final controller = inject<PluginsController>();
      if (controller.pluginList.isEmpty && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.extension_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
            title: const Text('欢迎使用樱花动漫'),
            content: const Text('你还没有添加规则，需要先添加规则才能正常使用。\n\n是否继续添加规则？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('返回'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.pushNamed('/settings/plugin/');
                },
                child: const Text('继续'),
              ),
            ],
          ),
        );
      }
    } catch (_) {}
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

  // ========================== 云端同步拆分 ==========================

  /// 弹出菜单让用户选择上传或下载
  Future<void> _syncCloud(BuildContext context) async {
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
              leading: const Icon(Icons.cloud_upload_rounded, color: Colors.green),
              title: const Text('上传本地数据到云端'),
              subtitle: const Text('用本地数据覆盖云端（本地优先）'),
              onTap: () => Navigator.pop(context, 'upload'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_rounded, color: Colors.blue),
              title: const Text('从云端恢复数据'),
              subtitle: const Text('用云端数据覆盖本地（换设备时使用）'),
              onTap: () => Navigator.pop(context, 'download'),
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
    if (action == null) return;
    if (action == 'upload') {
      await _uploadToCloud(context);
    } else if (action == 'download') {
      await _downloadFromCloud(context);
    }
  }

  /// 上传本地数据到云端（覆盖云端）
  Future<void> _uploadToCloud(BuildContext context) async {
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
              Flexible(child: Text('正在上传本地数据到云端…')),
            ],
          ),
        ),
      );
      // ⚠️ 您需要在 KazumiSyncService 中实现 uploadAll()
      final results = await KazumiSyncService.uploadAll();
      if (!context.mounted) return;
      KazumiDialog.dismiss();
      KazumiDialog.show(
        builder: (context) => AlertDialog(
          title: const Text('上传结果'),
          content: Text(results.join('\n')),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: const Text('好的'),
            ),
          ],
        ),
      );
      // 上传后刷新界面（但上传是本地覆盖云端，本地无变化，所以只需刷新显示）
      setState(() {});
    } finally {
      _syncingCloud = false;
    }
  }

  /// 从云端下载数据覆盖本地
  Future<void> _downloadFromCloud(BuildContext context) async {
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
              Flexible(child: Text('正在从云端下载数据…')),
            ],
          ),
        ),
      );
      // ⚠️ 您需要在 KazumiSyncService 中实现 downloadAll()
      final results = await KazumiSyncService.downloadAll();
      if (!context.mounted) return;
      KazumiDialog.dismiss();
      KazumiDialog.show(
        builder: (context) => AlertDialog(
          title: const Text('下载结果'),
          content: Text(results.join('\n')),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: const Text('好的'),
            ),
          ],
        ),
      );
      // 下载后重新加载本地数据（历史、目标等）
      _loadRecentHistories();
      _loadGoal();
      setState(() {});
    } finally {
      _syncingCloud = false;
    }
  }

  // ========================== 账号与数据管理 ==========================

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
              leading: const Icon(Icons.security_rounded, color: Colors.blue),
              title: const Text('安全中心'),
              subtitle: const Text('登录记录 / 设备管理'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SecurityCenterPage()),
                );
              },
            ),
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
    final textTheme = Theme.of(context).textTheme;
    final bangumiLoggedIn =
        GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;

    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text(
          '我的',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        needTopOffset: false,
        actions: [
          if (AuthService.isLoggedIn)
            IconButton(
              tooltip: '隐私设置',
              icon: const Icon(Icons.privacy_tip_outlined, size: 22),
              onPressed: () {
                final navContext = rootNavigatorKey.currentContext;
                if (navContext == null || !navContext.mounted) return;
                Navigator.of(navContext).push(
                  MaterialPageRoute(builder: (_) => const PrivacySettingsPage()),
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
            child: IconButton(
              tooltip: '全部设置',
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, size: 18, color: colorScheme.onSurface),
                    const SizedBox(width: 6),
                    Text('设置', style: TextStyle(fontSize: 13, color: colorScheme.onSurface)),
                  ],
                ),
              ),
              onPressed: () => context.pushNamed('/settings/'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final inset = constraints.maxWidth < 600 ? 16.0 : 32.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(inset, 8, inset, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── 个人中心 + 头像/登录/好友 ──
                      _buildHeader(colorScheme, textTheme, bangumiLoggedIn),
                      const SizedBox(height: 20),
                      // ── 本周目标 ──
                      _buildWeeklyGoal(colorScheme, textTheme),
                      const SizedBox(height: 12),
                      // ── 规则设置（紧挨着偏好设置，无间距）──
                      _buildRulesTile(colorScheme, textTheme),
                      // ── 偏好设置（紧挨着规则，无间距）──
                      _buildPreferencesPanel(colorScheme, textTheme),
                      const SizedBox(height: 12),
                      // ── 历史记录 + 离线下载（一行）──
                      Row(
                        children: [
                          Expanded(
                            child: _buildToolTile(
                              colorScheme, textTheme,
                              icon: Icons.history_rounded,
                              title: '历史记录',
                              caption: '查看观看记录',
                              color: colorScheme.secondaryContainer,
                              foreground: colorScheme.onSecondaryContainer,
                              onTap: () => context.pushNamed('/settings/history/'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildToolTile(
                              colorScheme, textTheme,
                              icon: Icons.download_rounded,
                              title: '离线下载',
                              caption: '管理离线内容',
                              color: colorScheme.tertiaryContainer,
                              foreground: colorScheme.onTertiaryContainer,
                              onTap: () => context.pushNamed('/settings/download/'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // ── 同步 + 清除缓存（一行）──
                      Row(
                        children: [
                          Expanded(
                            child: _buildToolTile(
                              colorScheme, textTheme,
                              icon: Icons.cloud_sync_rounded,
                              title: '同步',
                              caption: '跨设备同步数据',
                              color: colorScheme.surfaceContainer,
                              foreground: colorScheme.onSurface,
                              onTap: () => context.pushNamed('/settings/sync'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildToolTile(
                              colorScheme, textTheme,
                              icon: Icons.cleaning_services_rounded,
                              title: '清除缓存',
                              caption: '释放存储空间',
                              color: colorScheme.surfaceContainer,
                              foreground: colorScheme.onSurface,
                              onTap: () => _showCacheCleanup(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // ── 关于樱花动漫 ──
                      Center(
                        child: TextButton.icon(
                          onPressed: () => context.pushNamed('/settings/about/'),
                          icon: const Icon(Icons.info_outline_rounded, size: 18),
                          label: const Text('关于樱花动漫'),
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── 个人中心头部（头像可点击管理）──
  Widget _buildHeader(ColorScheme colorScheme, TextTheme textTheme, bool bangumiLoggedIn) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '个人中心',
                style: textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AuthService.isLoggedIn
                    ? '欢迎回来，${_socialProfile?.nickname ?? '用户'}'
                    : '登录以同步数据',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // 头像（已登录时可点击管理）
        GestureDetector(
          onTap: AuthService.isLoggedIn
              ? () {
                  // 点击头像进入管理页面
                  final navContext = rootNavigatorKey.currentContext;
                  if (navContext == null || !navContext.mounted) return;
                  // 跳转到安全中心
                  final navContext = rootNavigatorKey.currentContext;
                  if (navContext == null || !navContext.mounted) return;
                  Navigator.of(navContext).push(
                    MaterialPageRoute(builder: (_) => const SecurityCenterPage()),
                  );
                }
              : () {
                  final navContext = rootNavigatorKey.currentContext;
                  if (navContext == null || !navContext.mounted) return;
                  Navigator.of(navContext).push(
                    MaterialPageRoute(builder: (_) => const KazumiLoginPage()),
                  );
                },
          child: CircleAvatar(
            radius: 26,
            backgroundColor: AuthService.isLoggedIn
                ? Colors.green.withValues(alpha: 0.1)
                : colorScheme.primary.withValues(alpha: 0.1),
            child: AuthService.isLoggedIn && _socialProfile != null && _socialProfile!.avatar.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: NetworkImgLayer(
                      width: 52,
                      height: 52,
                      src: SocialService.proxiedAvatar(_socialProfile!.avatar),
                    ),
                  )
                : Icon(
                    AuthService.isLoggedIn ? Icons.check_circle_rounded : Icons.person_add_rounded,
                    color: AuthService.isLoggedIn ? Colors.green : colorScheme.primary,
                    size: 28,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        // 好友
        _buildAccountAction(
          colorScheme: colorScheme,
          icon: Icons.people_rounded,
          title: '好友',
          color: colorScheme.tertiary,
          badge: _friendRequestCount,
          onTap: () {
            if (!AuthService.isLoggedIn) {
              KazumiDialog.showToast(message: '请先登录樱花动漫账号');
              return;
            }
            final navContext = rootNavigatorKey.currentContext;
            if (navContext == null || !navContext.mounted) return;
            Navigator.of(navContext).push(
              MaterialPageRoute(builder: (_) => const FriendsPage()),
            ).then((_) => _loadSocialProfile());
          },
        ),
      ],
    );
  }

  Widget _buildAccountAction({
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 22),
              ),
              if (badge > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
        ],
      ),
    );
  }

  // ── 本周目标 ──
  Widget _buildWeeklyGoal(ColorScheme colorScheme, TextTheme textTheme) {
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('本周目标', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            if (weeklyGoal <= 0)
              Column(
                children: [
                  Text('本周还没设定目标，本周已看 $thisWeekEpisodes 集',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() => weeklyGoal = 5);
                      GStorage.putSetting(SettingsKeys.weeklyWatchGoal, 5);
                    },
                    child: const Text('设定目标（5 集 / 周）'),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('本周已看 $thisWeekEpisodes / $weeklyGoal 集',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: weeklyGoal > 1
                            ? () {
                                setState(() => weeklyGoal--);
                                GStorage.putSetting(SettingsKeys.weeklyWatchGoal, weeklyGoal);
                              }
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() => weeklyGoal++);
                          GStorage.putSetting(SettingsKeys.weeklyWatchGoal, weeklyGoal);
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
                    thisWeekEpisodes >= weeklyGoal ? '🎉 本周目标已完成！' : '还差 ${weeklyGoal - thisWeekEpisodes} 集达成目标',
                    style: TextStyle(
                      fontSize: 12,
                      color: thisWeekEpisodes >= weeklyGoal ? Colors.green : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── 规则设置大卡片 ──
  Widget _buildRulesTile(ColorScheme colorScheme, TextTheme textTheme) {
    return Material(
      color: colorScheme.primary,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(28),
        topRight: Radius.circular(64),
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => context.pushNamed('/settings/plugin/'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('规则设置',
                  style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: colorScheme.onPrimary)),
              const SizedBox(height: 6),
              Text('管理番剧来源', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onPrimary)),
              const SizedBox(height: 32),
              Container(
                width: 52,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.arrow_forward_rounded, color: colorScheme.primary, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 工具磁贴 ──
  Widget _buildToolTile(
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required IconData icon,
    required String title,
    required String caption,
    required Color color,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 28, color: foreground),
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded, size: 18, color: foreground),
                ],
              ),
              const SizedBox(height: 20),
              Text(title,
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: foreground)),
              const SizedBox(height: 4),
              Text(caption,
                  style: textTheme.bodySmall?.copyWith(color: foreground, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }

  // ── 偏好设置面板（全宽一行）──
  Widget _buildPreferencesPanel(ColorScheme colorScheme, TextTheme textTheme) {
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('偏好设置',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildPrefButton(colorScheme, Icons.palette_rounded, '外观', () => context.pushNamed('/settings/theme'))),
                const SizedBox(width: 8),
                Expanded(child: _buildPrefButton(colorScheme, Icons.play_circle_rounded, '播放', () => context.pushNamed('/settings/player'))),
                const SizedBox(width: 8),
                Expanded(child: _buildPrefButton(colorScheme, Icons.subtitles_rounded, '弹幕', () => context.pushNamed('/settings/danmaku/'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrefButton(ColorScheme colorScheme, IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, size: 28, color: colorScheme.onSecondaryContainer),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSecondaryContainer)),
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
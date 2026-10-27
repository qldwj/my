import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:yhdm/bean/card/bangumi_history_card.dart';
import 'package:yhdm/bean/card/network_img_layer.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/widget/settings_section_card.dart';
import 'package:yhdm/bean/widget/bangumi_avatar.dart';
import 'package:yhdm/request/apis/bangumi_api.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/modules/history/history_module.dart';
import 'package:yhdm/navigation.dart';
import 'package:yhdm/pages/my/bangumi_login_page.dart';
import 'package:yhdm/pages/my/checkin_page.dart';
import 'package:yhdm/pages/my/kazumi_login_page.dart';
import 'package:yhdm/pages/my/qrcode_login_page.dart';
import 'package:yhdm/pages/my/security_center_page.dart';
import 'package:yhdm/services/checkin_service.dart';
import 'package:yhdm/services/presence_heartbeat.dart';
import 'package:yhdm/plugins/plugins_controller.dart';
import 'package:yhdm/repositories/history_repository.dart';
import 'package:yhdm/services/auth_service.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/social/social_service.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/sync/kazumi_sync_service.dart';
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
  String _bangumiAvatarUrl = '';
  String _bangumiName = '';
  SocialProfile? _socialProfile;

  @override
  void initState() {
    super.initState();
    // ⭐ 全局登录失效回调：本地 token 失效（如重装被系统备份恢复但服务器已过期）
    // 时自动清除 token、刷新为未登录并提示重新登录，避免全部接口报「登录已过期」。
    AuthService.onAuthFailed = () {
      if (mounted) {
        setState(() {});
        KazumiDialog.showToast(
          message: AppLocalizations.of(context)!.setGLoginExpired,
          duration: const Duration(seconds: 3),
        );
      }
    };
    // ⭐ 全局登录/绑定状态变化：登录/绑定成功后立即刷新账号区，无需退出页面
    AuthService.onLoginChanged = () {
      if (mounted) _refreshAfterLogin();
    };
    _loadRecentHistories();
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
        final l10n = AppLocalizations.of(context)!;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.extension_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.setGWelcomeTitle),
            content: Text(l10n.setGWelcomeNoRulesBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.setGBack),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.pushNamed('/settings/plugin/');
                },
                child: Text(l10n.setGContinueLabel),
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
    // 🆕 把当前账号同步进「切换账号」列表（昵称/头像/uid，持久保存）
    if (profile != null && AuthService.isLoggedIn) {
      AuthService.upsertCurrentAccount(
        nickname: profile.nickname,
        avatar: profile.avatar,
        uid: profile.uid,
      );
    }
    // 🆕 登录即取消销毁（7 天冷静期规则）
    final status = await SocialService.deleteStatus();
    if (status?.pending == true) {
      await SocialService.cancelDelete();
    }
  }

  /// 🆕 登录/绑定成功后即时刷新账号区（昵称/头像/称号/好友红点）
  void _refreshAfterLogin() {
    if (!mounted) return;
    _loadSocialProfile();
    _loadBangumiUser();
  }

  /// 已登录 Bangumi 时拉取头像/昵称（走 api.kazumi.fyi 镜像）
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
    final l10n = AppLocalizations.of(context)!;
    final nicknameController = TextEditingController(text: profile.nickname);
    var currentAvatar = profile.avatar;
    var uploading = false;

    await showModalBottomSheet<void>(
      context: context,
sheetAnimationStyle: kSheetAnimationStyle,
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
              Text(l10n.setGProfile,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
                            KazumiDialog.showToast(message: l10n.setGImageTooLarge);
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
                            KazumiDialog.showToast(message: l10n.setGAvatarUpdated);
                          } else {
                            KazumiDialog.showToast(message: l10n.setGErrorToast(msg: error));
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
                decoration: InputDecoration(
                  labelText: l10n.setGNickname,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.cancel),
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
                          KazumiDialog.showToast(message: l10n.setGNicknameUpdated);
                        } else {
                          KazumiDialog.showToast(message: l10n.setGErrorToast(msg: error));
                        }
                      },
                      child: Text(l10n.save),
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
    final l10n = AppLocalizations.of(context)!;
    final cacheSize = await _getCacheSize();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.setGCacheCleanup),
        content: Text(
          l10n.setGCacheCleanupBody(size: _formatSize(cacheSize)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
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
                      KazumiDialog.showToast(message: l10n.setGCacheCleared);
                    }
                  },
            child: Text(l10n.setGCleanNow),
          ),
        ],
      ),
    );
  }

  // ========================== 云端同步拆分 ==========================

  /// 弹出菜单让用户选择上传或下载
  Future<void> _syncCloud(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    if (!AuthService.isLoggedIn) {
      KazumiDialog.showToast(message: l10n.setGPleaseLoginFirst);
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
sheetAnimationStyle: kSheetAnimationStyle,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_upload_rounded, color: Colors.green),
              title: Text(l10n.setGUploadToCloud),
              subtitle: Text(l10n.setGUploadLocalOverCloud),
              onTap: () => Navigator.pop(context, 'upload'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_rounded, color: Colors.blue),
              title: Text(l10n.setGRestoreFromCloud),
              subtitle: Text(l10n.setGDownloadCloudOverLocal),
              onTap: () => Navigator.pop(context, 'download'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l10n.cancel),
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
    final l10n = AppLocalizations.of(context)!;
    if (_syncingCloud) return;
    _syncingCloud = true;
    try {
      KazumiDialog.show(
        clickMaskDismiss: false,
        builder: (context) => AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text(l10n.setGUploading)),
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
          title: Text(l10n.setGUploadResult),
          content: Text(results.join('\n')),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: Text(l10n.setAOk),
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
    final l10n = AppLocalizations.of(context)!;
    if (_syncingCloud) return;
    _syncingCloud = true;
    try {
      KazumiDialog.show(
        clickMaskDismiss: false,
        builder: (context) => AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text(l10n.setGDownloading)),
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
          title: Text(l10n.setGDownloadResult),
          content: Text(results.join('\n')),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: Text(l10n.setAOk),
            ),
          ],
        ),
      );
      // 下载后重新加载本地数据（历史、目标等）
      _loadRecentHistories();
      setState(() {});
    } finally {
      _syncingCloud = false;
    }
  }

  // ========================== 账号与数据管理 ==========================

  /// 账号与数据管理：清除云端数据 / 注销账号
  Future<void> _manageAccountData(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    if (!AuthService.isLoggedIn) {
      KazumiDialog.showToast(message: l10n.setGPleaseLoginFirst);
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
sheetAnimationStyle: kSheetAnimationStyle,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.security_rounded, color: Colors.blue),
              title: Text(l10n.setGSecurityCenter),
              subtitle: Text(l10n.setGLoginRecordsDeviceMgmt),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SecurityCenterPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_off_rounded),
              title: Text(l10n.setGClearCloudData),
              subtitle: Text(l10n.setGClearCloudDataSubtitle),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded,
                  color: Colors.red),
              title: Text(l10n.setGDeleteAccount,
                  style: const TextStyle(color: Colors.red)),
              subtitle: Text(l10n.setGDeleteAccountSubtitle),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l10n.cancel),
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
          title: Text(l10n.setGClearCloudData),
          content: Text(l10n.setGClearCloudConfirmBody),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(popWith: false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => KazumiDialog.dismiss(popWith: true),
              child: Text(l10n.setGClear),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      final res = await AuthService.clearData();
      if (!mounted) return;
      KazumiDialog.showToast(
        message: res['error'] != null
            ? l10n.setGErrorToast(msg: res['error'].toString())
            : l10n.setGCloudDataCleared,
      );
    } else if (action == 'delete') {
      // 🆕 账号销毁：直接删除（后端已去掉 7 天冷静期）
      final confirm = await KazumiDialog.show<bool>(
        builder: (context) => AlertDialog(
          title: Text(l10n.setGAccountDestruction,
              style: const TextStyle(color: Colors.red)),
          content: Text(l10n.setGAccountDestructionBody),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(popWith: false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => KazumiDialog.dismiss(popWith: true),
              child: Text(l10n.setGConfirmDestroy),
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
            ? l10n.setGErrorToast(msg: error)
            : l10n.setGAccountDeleted,
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

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bangumiLoggedIn =
        GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim().isNotEmpty;

    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text(
          l10n.setGTabMine,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        needTopOffset: false,
        actions: [
          if (AuthService.isLoggedIn)
            IconButton(
              tooltip: '在线状态上报',
              icon: Icon(
                GStorage.getSetting(SettingsKeys.presenceVisibilityEnabled)
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 22,
                color: GStorage.getSetting(SettingsKeys.presenceVisibilityEnabled)
                    ? colorScheme.onSurface
                    : Colors.grey,
              ),
              onPressed: () async {
                final cur = GStorage.getSetting(SettingsKeys.presenceVisibilityEnabled);
                await GStorage.putSetting(SettingsKeys.presenceVisibilityEnabled, !cur);
                // 重启/停止 App 级心跳（必须在 putSetting 之后，否则 refresh() 读到旧值）
                PresenceHeartbeat.instance.refresh();
                if (mounted) setState(() {});
                KazumiDialog.showToast(
                  message: cur ? '已关闭在线状态上报' : '已开启在线状态上报',
                );
              },
            ),
          if (AuthService.isLoggedIn)
            IconButton(
              tooltip: l10n.setGScanLoginOtherDevice,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QrcodeLoginPage()),
                );
              },
            ),
          if (!AuthService.isLoggedIn)
            IconButton(
              tooltip: l10n.setGScanLogin,
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
              tooltip: l10n.setGAllSettings,
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
                    Text(l10n.settings, style: TextStyle(fontSize: 13, color: colorScheme.onSurface)),
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
                      const SizedBox(height: 24),
                      _sectionHeader(l10n.setGSectionPrefs),
                      const SizedBox(height: 8),
                      // ── 规则设置（紧挨着偏好设置，无间距）──
                      _buildRulesTile(colorScheme, textTheme),
                      // ── 偏好设置（紧挨着规则，无间距）──
                      _buildPreferencesPanel(context, colorScheme, textTheme),
                      const SizedBox(height: 24),
                      _sectionHeader(l10n.setGSectionData),
                      const SizedBox(height: 8),
                      // ── 历史记录 + 离线下载（一行）──
                      Row(
                        children: [
                          Expanded(
                            child: _buildToolTile(
                              colorScheme, textTheme,
                              icon: Icons.history_rounded,
                              title: l10n.setGHistory,
                              caption: l10n.setGViewWatchHistory,
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
                              title: l10n.setGOfflineDownload,
                              caption: l10n.setGManageOfflineContent,
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
                              title: l10n.setGSync,
                              caption: l10n.setGCrossDeviceSync,
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
                              title: l10n.setGClearCache,
                              caption: l10n.setGFreeStorage,
                              color: colorScheme.surfaceContainer,
                              foreground: colorScheme.onSurface,
                              onTap: () => _showCacheCleanup(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // ── 追番打卡（压缩成一行）──
                      _buildCompactTile(
                        colorScheme,
                        textTheme,
                        icon: Icons.local_fire_department_rounded,
                        title: l10n.setGCheckin,
                        color: colorScheme.tertiaryContainer,
                        foreground: colorScheme.onTertiaryContainer,
                        onTap: () => context.pushNamed('/tab/my/checkin'),
                      ),
                      const SizedBox(height: 24),
                      _sectionHeader(l10n.setGSectionAbout),
                      const SizedBox(height: 8),
                      // ── 关于樱花动漫 ──
                      Center(
                        child: TextButton.icon(
                          onPressed: () => context.pushNamed('/settings/about/'),
                          icon: const Icon(Icons.info_outline_rounded, size: 18),
                          label: Text(l10n.setGAboutApp),
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
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.setGAccountCenter,
                style: textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AuthService.isLoggedIn
                    ? l10n.setGWelcomeBack(nickname: _socialProfile?.nickname ?? l10n.setGUserFallback)
                    : l10n.setGLoginToSync,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (AuthService.isLoggedIn && _socialProfile != null && _socialProfile!.uid.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.setGUserIdLabel(uid: _socialProfile!.uid),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
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
                  // 跳转到账号绑定页面
                  final navContext = rootNavigatorKey.currentContext;
                  if (navContext == null || !navContext.mounted) return;
                  Navigator.of(navContext).push(
                    MaterialPageRoute(builder: (_) => const KazumiLoginPage()),
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
        // 🆕 切换账号（多账号快速切换，账号列表持久保存，重开 App 不丢）
        _buildAccountAction(
          colorScheme: colorScheme,
          icon: Icons.switch_account_rounded,
          title: l10n.setGSwitchAccountShort,
          color: colorScheme.primary,
          onTap: () => _showAccountSwitcher(),
        ),
      ],
    );
  }

  /// 🆕 账号快速切换面板
  void _showAccountSwitcher() {
    final l10n = AppLocalizations.of(context)!;
    final currentToken = AuthService.getLocalToken();
    final saved = AuthService.getSavedAccounts();
    showModalBottomSheet<void>(
      context: context,
sheetAnimationStyle: kSheetAnimationStyle,
      useRootNavigator: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Row(
                children: [
                  Icon(Icons.switch_account_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(l10n.setGSwitchAccountsTitle,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              if (AuthService.isLoggedIn)
                ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.person_rounded)),
                  title: Text(_socialProfile?.nickname?.isNotEmpty == true
                      ? _socialProfile!.nickname
                      : l10n.setGCurrentAccount),
                  subtitle: Text(l10n.setGCurrentlyActive),
                  trailing: const Icon(Icons.check_circle_rounded,
                      color: Colors.green),
                ),
              if (saved.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(l10n.setGSavedAccounts,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ),
              for (final acc in saved.where((a) => a.token != currentToken)) ...[
                ListTile(
                  leading: CircleAvatar(
                    child: Text(acc.nickname.isNotEmpty
                        ? String.fromCharCode(acc.nickname.runes.first)
                        : '?'),
                  ),
                  title: Text(acc.nickname.isNotEmpty ? acc.nickname : l10n.setGUnnamedAccount),
                  subtitle: Text(acc.uid.isNotEmpty ? l10n.setGUserIdLabel(uid: acc.uid) : l10n.setGLoggedInBefore),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'remove') {
                        await AuthService.removeSavedAccount(acc.token);
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _loadSocialProfile();
                        if (mounted) setState(() {});
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'remove', child: Text(l10n.setGRemoveFromList)),
                    ],
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AuthService.switchAccount(acc.token);
                    await _loadSocialProfile();
                    if (mounted) {
                      KazumiDialog.showToast(
                          message: l10n.setGSwitchedToAccount(name: acc.nickname.isNotEmpty ? acc.nickname : l10n.setGThisAccount));
                    }
                  },
                ),
              ],
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_rounded),
                title: Text(l10n.setGLoginNewAccount),
                onTap: () {
                  Navigator.pop(ctx);
                  final navContext = rootNavigatorKey.currentContext;
                  if (navContext == null || !navContext.mounted) return;
                  Navigator.of(navContext)
                      .push(MaterialPageRoute(
                          builder: (_) => const KazumiLoginPage()))
                      .then((_) => _loadSocialProfile());
                },
              ),
              if (AuthService.isLoggedIn)
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: Text(l10n.setGLogoutCurrentAccount),
                  subtitle: Text(l10n.setGLogoutSubtitle),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: Text(l10n.setGLogout),
                        content: Text(l10n.setGLogoutConfirmBody),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: Text(l10n.cancel)),
                          FilledButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: Text(l10n.exit)),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    AuthService.clearLocalToken();
                    SocialService.clearProfileCache();
                    await _loadSocialProfile();
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        );
      },
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

  // ── 规则设置大卡片 ──
  Widget _buildRulesTile(ColorScheme colorScheme, TextTheme textTheme) {
    final l10n = AppLocalizations.of(context)!;
    // 🆕 规则更新红点（启动检测写入，进入规则页后清零）
    final ruleUpdateCount =
        GStorage.getSetting(SettingsKeys.ruleUpdateCount);
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
        onTap: () async {
          await context.pushNamed('/settings/plugin/');
          if (!mounted) return;
          GStorage.putSetting(SettingsKeys.ruleUpdateCount, 0);
          setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.setGRuleSettings,
                        style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onPrimary)),
                  ),
                  if (ruleUpdateCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Badge(count: ruleUpdateCount),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(l10n.setGManageSources, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onPrimary)),
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

  // ── 一行紧凑列表项（48dp）──
  Widget _buildCompactTile(
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required IconData icon,
    required String title,
    required Color color,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: foreground),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: foreground),
              ],
            ),
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
  // 🆕 使用次数排序：点击入口使用次数 +1，次数越多的排越靠前（相同次数保持默认顺序）。
  Widget _buildPreferencesPanel(BuildContext context, ColorScheme colorScheme, TextTheme textTheme) {
    final l10n = AppLocalizations.of(context)!;
    final counts = _readPreferenceUsage();
    final entries = [
      ('theme', Icons.palette_rounded, l10n.setGPrefAppearance, '/settings/theme'),
      ('player', Icons.play_circle_rounded, l10n.setGPrefPlayer, '/settings/player'),
      ('danmaku', Icons.subtitles_rounded, l10n.setGPrefDanmaku, '/settings/danmaku/'),
    ];
    // 按使用次数降序排列，次数相同保持默认顺序（稳定排序）
    final sorted = [...entries]..sort((a, b) {
        final diff = (counts[b.$1] ?? 0).compareTo(counts[a.$1] ?? 0);
        if (diff != 0) return diff;
        return entries.indexOf(a).compareTo(entries.indexOf(b));
      });

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.setGPreferences,
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < sorted.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _buildPrefButton(
                      colorScheme,
                      sorted[i].$2,
                      sorted[i].$3,
                      counts[sorted[i].$1] ?? 0,
                      () => _openPreference(sorted[i].$1, sorted[i].$4),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 读取各偏好入口的使用次数（JSON: {"theme":3,"player":5,"danmaku":2}）
  Map<String, int> _readPreferenceUsage() {
    final result = <String, int>{};
    try {
      final raw = GStorage.getSetting(SettingsKeys.prefUsageCount);
      if (raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in map.entries) {
          result[e.key] = (e.value as num?)?.toInt() ?? 0;
        }
      }
    } catch (_) {}
    return result;
  }

  /// 点击偏好入口：使用次数 +1 并保存，然后跳转对应设置页
  Future<void> _openPreference(String id, String route) async {
    try {
      final counts = _readPreferenceUsage();
      counts[id] = (counts[id] ?? 0) + 1;
      await GStorage.putSetting(
        SettingsKeys.prefUsageCount,
        jsonEncode(counts),
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    context.pushNamed(route);
  }

  Widget _buildPrefButton(ColorScheme colorScheme, IconData icon, String label,
      int count, VoidCallback onTap) {
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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 28, color: colorScheme.onSecondaryContainer),
                ],
              ),
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
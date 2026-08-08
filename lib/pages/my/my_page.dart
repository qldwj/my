import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/bangumi_history_card.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/settings_section_card.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/my/bangumi_login_page.dart';
import 'package:kazumi/pages/my/kazumi_login_page.dart';
import 'package:kazumi/pages/my/qrcode_login_page.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/kazumi_sync_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadRecentHistories();
    _loadGoal();
    _loadBangumiUser();
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

  /// 缓存清理弹窗：显示图片缓存占用 + 一键清理
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
                    await DefaultCacheManager().emptyCache();
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
      final confirm = await KazumiDialog.show<bool>(
        builder: (context) => AlertDialog(
          title: const Text('注销账号', style: TextStyle(color: Colors.red)),
          content: const Text('将删除账号和全部云端数据，不可恢复，且会退出登录。确定注销？'),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(popWith: false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => KazumiDialog.dismiss(popWith: true),
              child: const Text('确认注销'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      final res = await AuthService.deleteAccount();
      AuthService.clearLocalToken();
      if (!mounted) return;
      KazumiDialog.showToast(
        message:
            res['error'] != null ? '❌ ${res['error']}' : '✅ 账号已注销',
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
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BangumiLoginPage()),
                    ),
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
                      child: Icon(
                        AuthService.isLoggedIn
                            ? Icons.check_circle
                            : Icons.person_add,
                        color: AuthService.isLoggedIn
                            ? Colors.green.shade600
                            : Colors.blue.shade600,
                      ),
                    ),
                    title: AuthService.isLoggedIn ? '樱花动漫账号已登录' : '樱花动漫账号',
                    description: AuthService.isLoggedIn
                        ? '点击管理账号'
                        : '登录后可同步收藏与进度',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const KazumiLoginPage()),
                    ),
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

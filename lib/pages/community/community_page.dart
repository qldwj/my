import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/card/network_img_layer.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/request/apis/bangumi_api.dart';
import 'package:yhdm/services/auth_service.dart';
import 'package:yhdm/services/presence_service.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';

/// 社区页：实时展示当前在线总人数 / 正在观看的动漫
///
/// 数据源：PresenceService.stats()（后端 ?action=stats，60s 一次）
/// 与心跳频率保持一致，服务端 180s 未心跳即判为离线
class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  /// 与心跳相同的刷新间隔
  static const Duration _refreshInterval = Duration(seconds: 60);

  Timer? _timer;
  bool _loading = false;
  Map<String, dynamic> _stats = {};
  final Map<int, BangumiItem> _subjectCache = {};
  final Set<int> _inflightFetch = {};
  DateTime? _snapshotAt;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshInterval, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await PresenceService.stats();
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() {
          _stats = res;
          _snapshotAt = DateTime.now();
        });
        // 对 playing 里出现的 subject_id 补拉 Bangumi 详情
        _ensureSubjects((res['playing'] as List?) ?? []);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 并发拉取 playing 列表里缺失的 Bangumi 详情；已有的直接跳过
  Future<void> _ensureSubjects(List playing) async {
    final ids = <int>[];
    for (final p in playing) {
      if (p is! Map) continue;
      final subject = p['subject'];
      if (subject is! Map) continue;
      final sid = (subject['subject_id'] as num?)?.toInt() ?? 0;
      if (sid <= 0) continue;
      if (_subjectCache.containsKey(sid) || _inflightFetch.contains(sid)) continue;
      ids.add(sid);
    }
    if (ids.isEmpty) return;
    await Future.wait([
      for (final sid in ids) _fetchOneSubject(sid),
    ]);
    if (mounted) setState(() {});
  }

  Future<void> _fetchOneSubject(int sid) async {
    _inflightFetch.add(sid);
    try {
      final item = await BangumiApi.getBangumiInfoByID(sid);
      if (item != null) _subjectCache[sid] = item;
    } catch (_) {
      // 单条失败不影响其它
    } finally {
      _inflightFetch.remove(sid);
    }
  }

  /// 从 stats 响应里聚合出「当前正在看哪些番剧 & 每部有多少人看」
  ///
  /// 返回 [{ subject_id, item, viewers }]
  List<MapEntry<int, int>> _playingAggregated() {
    final counters = <int, int>{};
    for (final p in (_stats['playing'] as List?) ?? []) {
      if (p is! Map) continue;
      final subject = p['subject'];
      if (subject is! Map) continue;
      final sid = (subject['subject_id'] as num?)?.toInt() ?? 0;
      if (sid <= 0) continue;
      counters[sid] = (counters[sid] ?? 0) + 1;
    }
    final sorted = counters.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }

  String _summaryText(Map<String, dynamic> summary) {
    final online = (summary['online'] as num?)?.toInt() ?? 0;
    final playing = (summary['playing'] as num?)?.toInt() ?? 0;
    final offline = (summary['offline'] as num?)?.toInt() ?? 0;
    return '$online 在线 · $playing 在播 · $offline 离线';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final summary = (_stats['summary'] as Map?) ?? {};
    final playingList = _playingAggregated();
    final isLoggedIn = AuthService.isLoggedIn;

    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        title: const Text('社区'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildIdentityChip(isLoggedIn: isLoggedIn),
          ),
          IconButton(
            tooltip: '刷新',
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 22),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isLoggedIn) _buildGuestBanner(),
          _buildHeader(summary, l10n),
          _buildSectionTitle('正在看', playingList.length),
          if (playingList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _stats.isEmpty
                      ? (_loading ? '加载中…' : '暂无数据，下拉刷新')
                      : '当前没有人在播',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, boxConstraints) {
                  final isWide = boxConstraints.maxWidth >= 600;
                  final cols = isWide ? (boxConstraints.maxWidth ~/ 180).clamp(2, 6) : 2;
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: playingList.length,
                    itemBuilder: (context, i) {
                      final entry = playingList[i];
                      return _buildPlayingCard(entry.key, entry.value);
                    },
                  );
                },
              ),
            ),
          _buildFooter(_stats),
        ],
      ),
    );
  }

  Widget _buildIdentityChip({required bool isLoggedIn}) {
    final cs = Theme.of(context).colorScheme;
    if (!isLoggedIn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              '游客',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_rounded, size: 14, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            _currentDisplayName(),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onPrimaryContainer),
          ),
        ],
      ),
    );
  }

  /// 从本地缓存取当前登录用户名；未登录返回 '游客'
  String _currentDisplayName() {
    if (!AuthService.isLoggedIn) return '游客';
    final token = AuthService.getLocalToken() ?? '';
    final accounts = AuthService.getSavedAccounts();
    final current = accounts.where((a) => a.token == token).firstOrNull;
    final nickname = current?.nickname.trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    final email = AuthService.currentUserEmail ?? '';
    if (email.isNotEmpty && email.contains('@')) return email.split('@').first;
    return '我';
  }

  Widget _buildGuestBanner() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.tertiaryContainer.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: cs.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '你正在以游客身份浏览社区，你的在线状态不会被上报',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> summary, AppLocalizations l10n) {
    final online = (summary['online'] as num?)?.toInt() ?? 0;
    final playing = (summary['playing'] as num?)?.toInt() ?? 0;
    final devices = (summary['devices'] as Map?) ?? {};
    final deviceText = devices.entries
        .map((e) => '${e.key} ${e.value}')
        .join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$_online',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text('在线',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$playing 部在播',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_snapshotAt != null)
                    Text(
                      '更新 ${_formatTimeAgo(_snapshotAt!)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                ],
              ),
            ],
          ),
          if (deviceText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                deviceText,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayingCard(int subjectId, int viewers) {
    final item = _subjectCache[subjectId];
    final name = (item?.nameCn.isNotEmpty ?? false)
        ? item!.nameCn
        : (item?.name ?? '番剧 #$subjectId');
    final coverUrl = item?.images['large'] ?? item?.images['small'] ?? '';

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: item == null ? null : () => context.pushNamed('/info/', arguments: item),
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(builder: (context, boxConstraints) {
                  return NetworkImgLayer(
                    src: coverUrl,
                    width: boxConstraints.maxWidth,
                    height: boxConstraints.maxHeight,
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.people, size: 14),
                      const SizedBox(width: 4),
                      Text('$viewers 人在看', style: Theme.of(context).textTheme.bodySmall),
                      const Spacer(),
                      if (item != null && item.ratingScore > 0)
                        Text(
                          item.ratingScore.toStringAsFixed(1),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(Map<String, dynamic> stats) {
    final after = stats['offline_after_seconds'];
    final afterSec = after is int ? after : 180;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '心跳 ${afterSec}s 未更新即离线 · 数据每 60s 同步',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _formatTimeAgo(DateTime t) {
    final sec = DateTime.now().difference(t).inSeconds;
    if (sec < 5) return '刚刚';
    if (sec < 60) return '${sec}s 前';
    return '${sec ~/ 60} 分钟前';
  }
}

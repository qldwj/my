import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';

/// 观看统计页面
/// 展示月度/年度观看报告
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  // 统计数据
  int _totalAnime = 0;
  int _totalEpisodes = 0;
  int _totalWatchHours = 0;
  int _totalWatchMinutes = 0;
  int _thisMonthAnime = 0;
  int _thisMonthEpisodes = 0;
  int _thisMonthHours = 0;
  int _thisMonthMinutes = 0;
  int _collectCount = 0;
  String _favoriteTag = '';
  String _mostActiveDay = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _calculateStats();
  }

  void _calculateStats() {
    try {
      final historyRepo = HistoryRepository();
      final histories = historyRepo.getAllHistories();
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);

      // 标签统计
      final Map<String, int> tagCount = {};
      final Map<int, int> dayCount = {};

      for (final history in histories) {
        _totalAnime++;
        _totalEpisodes += history.progresses.length;

        // 计算总观看时长
        for (final prog in history.progresses.values) {
          final ms = prog.progress.inMilliseconds;
          _totalWatchMinutes += ms ~/ 60000;
        }

        // 本月统计
        if (history.lastWatchTime.isAfter(monthStart)) {
          _thisMonthAnime++;
          _thisMonthEpisodes += history.progresses.length;
          for (final prog in history.progresses.values) {
            final ms = prog.progress.inMilliseconds;
            _thisMonthMinutes += ms ~/ 60000;
          }
        }

        // 标签统计
        for (final tag in history.bangumiItem.tags) {
          tagCount[tag.name] = (tagCount[tag.name] ?? 0) + 1;
        }

        // 星期几活跃度
        final weekday = history.lastWatchTime.weekday;
        dayCount[weekday] = (dayCount[weekday] ?? 0) + 1;
      }

      // 最喜欢的标签
      if (tagCount.isNotEmpty) {
        final sorted = tagCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        _favoriteTag = sorted.first.key;
      }

      // 最活跃的日子
      if (dayCount.isNotEmpty) {
        final sorted = dayCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        const weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        _mostActiveDay = weekdays[sorted.first.key];
      }

      // 收藏统计
      _collectCount = GStorage.collectibles.length;

      _totalWatchHours = _totalWatchMinutes ~/ 60;
      _totalWatchMinutes = _totalWatchMinutes % 60;
      _thisMonthHours = _thisMonthMinutes ~/ 60;
      _thisMonthMinutes = _thisMonthMinutes % 60;
    } catch (_) {}

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const SysAppBar(title: Text('观看统计')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 总览卡片
                _buildOverviewCard(theme),
                const SizedBox(height: 16),

                // 本月数据
                _buildSectionTitle(theme, '本月概览'),
                const SizedBox(height: 8),
                _buildMonthCard(theme),
                const SizedBox(height: 16),

                // 详细统计
                _buildSectionTitle(theme, '详细统计'),
                const SizedBox(height: 8),
                _buildDetailCard(theme),

                const SizedBox(height: 16),
                // 趣味数据
                _buildSectionTitle(theme, '趣味数据'),
                const SizedBox(height: 8),
                _buildFunCard(theme),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildOverviewCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.bar_chart_rounded, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text('你的追番报告', style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(theme, '$_totalAnime', '看过番剧', Icons.movie),
                _buildStatItem(theme, '$_totalEpisodes', '总集数', Icons.playlist_play),
                _buildStatItem(theme, '${_collectCount}', '收藏', Icons.favorite),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(theme, '$_thisMonthAnime', '本月番剧', Icons.movie),
            _buildStatItem(theme, '$_thisMonthEpisodes', '本月集数', Icons.playlist_play),
            _buildStatItem(
              theme,
              '${_thisMonthHours}h ${_thisMonthMinutes}m',
              '本月时长',
              Icons.timer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildDetailRow(theme, '累计观看时长', '${_totalWatchHours}小时 ${_totalWatchMinutes}分钟', Icons.timer),
            const Divider(),
            _buildDetailRow(theme, '平均每部番剧', '${_totalEpisodes ~/ (_totalAnime > 0 ? _totalAnime : 1)}集', Icons.movie),
            const Divider(),
            _buildDetailRow(theme, '收藏数量', '$_collectCount 部', Icons.favorite),
            const Divider(),
            _buildDetailRow(theme, '看过番剧', '$_totalAnime 部', Icons.check_circle),
          ],
        ),
      ),
    );
  }

  Widget _buildFunCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildDetailRow(theme, '最喜欢的标签', _favoriteTag.isNotEmpty ? _favoriteTag : '暂无', Icons.tag),
            const Divider(),
            _buildDetailRow(theme, '最活跃的追番日', _mostActiveDay.isNotEmpty ? _mostActiveDay : '暂无', Icons.calendar_today),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(ThemeData theme, String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(label, style: theme.textTheme.bodyMedium),
        const Spacer(),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        )),
      ],
    );
  }
}

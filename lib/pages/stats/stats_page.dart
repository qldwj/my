import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/utils/device.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';

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

  // 本周周报数据
  int _weekEpisodes = 0;
  int _weekAnime = 0;
  int _weekMinutes = 0;
  String _weekTopAnime = '';
  String _weekActiveDay = '';

  @override
  void initState() {
    super.initState();
    _calculateStats();
    _calculateWeeklyReport();
  }

  /// ⭐ 统计本周（周一到今天）观看数据
  void _calculateWeeklyReport() {
    try {
      final historyRepo = HistoryRepository();
      final histories = historyRepo.getAllHistories();
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final mondayStart = DateTime(monday.year, monday.month, monday.day);

      final Map<String, int> animeEpCount = {};
      final Map<int, int> dayCount = {};

      for (final history in histories) {
        if (!history.lastWatchTime.isAfter(mondayStart)) continue;
        _weekAnime++;
        final eps = history.progresses.length;
        _weekEpisodes += eps;
        for (final prog in history.progresses.values) {
          _weekMinutes += prog.progress.inMilliseconds ~/ 60000;
        }
        final name = history.bangumiItem.nameCn.isNotEmpty
            ? history.bangumiItem.nameCn
            : history.bangumiItem.name;
        animeEpCount[name] = (animeEpCount[name] ?? 0) + eps;
        final weekday = history.lastWatchTime.weekday;
        dayCount[weekday] = (dayCount[weekday] ?? 0) + 1;
      }

      if (animeEpCount.isNotEmpty) {
        final sorted = animeEpCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        _weekTopAnime = sorted.first.key;
      }
      if (dayCount.isNotEmpty) {
        final sorted = dayCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        const weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        _weekActiveDay = weekdays[sorted.first.key];
      }
    } catch (_) {}
  }

  /// ⭐ 显示本周周报 + 分享
  void _showWeeklyReport() {
    final hours = _weekMinutes ~/ 60;
    final mins = _weekMinutes % 60;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📊 本周观看周报'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🆕 分享图预览（RepaintBoundary 截图用）
            Center(
              child: RepaintBoundary(
                key: _shareCardKey,
                child: _buildShareCard(
                  episodes: _weekEpisodes,
                  anime: _weekAnime,
                  hours: hours,
                  mins: mins,
                  topAnime: _weekTopAnime,
                  activeDay: _weekActiveDay,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('本周(周一起)你看了 $_weekEpisodes 集、$_weekAnime 部番'),
            const SizedBox(height: 6),
            Text('累计观看 $hours 小时 $mins 分钟'),
            if (_weekTopAnime.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('最爱看：《$_weekTopAnime》'),
            ],
            if (_weekActiveDay.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('最活跃的一天：$_weekActiveDay'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final text = '📊 我的本周观看周报\n'
                  '看了 $_weekEpisodes 集 / $_weekAnime 部番\n'
                  '累计 $hours 小时 $mins 分钟\n'
                  '${_weekTopAnime.isNotEmpty ? '最爱看：《$_weekTopAnime》\n' : ''}'
                  '${_weekActiveDay.isNotEmpty ? '最活跃：$_weekActiveDay\n' : ''}'
                  '—— 来自樱花动漫';
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('周报已复制，去粘贴分享吧 🎉')),
                );
              }
            },
            child: const Text('复制分享'),
          ),
          TextButton(
            onPressed: () async {
              await _captureShareImage();
            },
            child: const Text('保存为图片'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // 🆕 分享图截图 Key
  final GlobalKey _shareCardKey = GlobalKey();

  /// 生成周报分享卡片（固定尺寸，截图时按 3x 放大保证清晰）
  Widget _buildShareCard({
    required int episodes,
    required int anime,
    required int hours,
    required int mins,
    required String topAnime,
    required String activeDay,
  }) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6C5CE7), Color(0xFF3498DB)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 我的本周追番周报',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${DateTime.now().year}年${DateTime.now().month}月第${(DateTime.now().day / 7).ceil()}周',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _shareStat('集数', '$episodes 集'),
              _shareStat('番剧', '$anime 部'),
              _shareStat('时长', '$hours 时 $mins 分'),
            ],
          ),
          const SizedBox(height: 14),
          if (topAnime.isNotEmpty)
            Text(
              '🏆 最爱看：《$topAnime》',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          if (activeDay.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '🔥 最活跃：$activeDay',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 10),
          const Text(
            '来自 樱花动漫',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _shareStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  /// 截图分享卡片并保存（移动端存相册，桌面端存下载目录）
  Future<void> _captureShareImage() async {
    try {
      final boundary = _shareCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        KazumiDialog.showToast(message: '生成失败：未找到卡片');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final fileName =
          'YHDM_weekly_report_${DateTime.now().millisecondsSinceEpoch}.png';

      if (isDesktop()) {
        final dir = await getDownloadsDirectory();
        if (dir == null) {
          KazumiDialog.showToast(message: '未找到下载目录');
          return;
        }
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
      } else {
        final result = await SaverGallery.saveImage(
          bytes,
          fileName: fileName,
          skipIfExists: false,
        );
        // 保存结果静默处理，不弹多余 toast
        if (!result.isSuccess && mounted) {
          KazumiDialog.showToast(message: '保存失败：${result.errorMessage}');
        }
      }
    } catch (e) {
      KazumiDialog.showToast(message: '生成分享图失败：$e');
    }
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

                const SizedBox(height: 16),
                // ⭐ 本周周报
                _buildSectionTitle(theme, '本周周报'),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.auto_graph_rounded,
                        color: theme.colorScheme.primary),
                    title: const Text('生成本周观看周报'),
                    subtitle: Text(
                        '本周看了 $_weekEpisodes 集 / $_weekAnime 部番，点击查看并分享'),
                    onTap: _showWeeklyReport,
                  ),
                ),
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/video_source/speed_tester.dart';

/// 测速对话框 — 获取到剧集线路后进行测速和排序
class SpeedTestDialog {
  /// 显示测速对话框，对 roads 进行测速和排序
  ///
  /// [roads] 从 plugin.queryChapterRoads() 获取的线路列表
  /// 返回排序后的 roads，如果用户取消则返回原始 roads
  static Future<List<Road>> show({
    required BuildContext context,
    required List<Road> roads,
  }) async {
    if (roads.isEmpty) return roads;
    if (roads.length == 1) return roads; // 只有一个线路不用测

    final completer = Completer<List<Road>>();
    final sortedRoads = await showDialog<List<Road>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SpeedTestDialog(
        roads: roads,
      ),
    );

    return sortedRoads ?? roads;
  }
}

class _SpeedTestDialog extends StatefulWidget {
  final List<Road> roads;

  const _SpeedTestDialog({required this.roads});

  @override
  State<_SpeedTestDialog> createState() => _SpeedTestDialogState();
}

class _SpeedTestDialogState extends State<_SpeedTestDialog> {
  List<Road>? _sortedRoads;
  bool _testing = true;
  String _statusText = '正在测试各线路速度...';

  @override
  void initState() {
    super.initState();
    _runTests();
  }

  Future<void> _runTests() async {
    final sorted = await SpeedTester.testAndSortRoads(widget.roads);
    if (mounted) {
      setState(() {
        _sortedRoads = sorted;
        _testing = false;
        _statusText = '检测完成，已按速度排序';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _testing ? Icons.speed_rounded : Icons.check_circle_rounded,
            color: _testing ? theme.colorScheme.primary : Colors.green,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(_testing ? '正在测速' : '测速完成'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _testing ? _buildTesting(theme) : _buildResults(theme),
      ),
      actions: [
        if (!_testing)
          TextButton(
            onPressed: () => Navigator.pop(context, _sortedRoads),
            child: const Text('使用此排序播放'),
          ),
      ],
    );
  }

  Widget _buildTesting(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
        Text('正在测试 ${widget.roads.length} 个线路...',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text('最快线路将自动排在最前面',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_sortedRoads == null || _sortedRoads!.isEmpty) {
      return const Text('未获取到可用线路');
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 显示排序后的结果
          ..._sortedRoads!.asMap().entries.map((entry) =>
            _buildRoadItem(theme, entry.key, entry.value)),
          const SizedBox(height: 12),
          // 汇总信息
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withAlpha(60),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '最快线路「${_sortedRoads!.first.name}」已排在最前面',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadItem(ThemeData theme, int index, Road road) {
    // 根据排名显示不同颜色
    Color dotColor;
    String rankLabel;
    if (index == 0) {
      dotColor = Colors.green;
      rankLabel = '🟢 最快';
    } else if (index == 1) {
      dotColor = Colors.lightGreen;
      rankLabel = '🟢';
    } else if (index == 2) {
      dotColor = Colors.orange;
      rankLabel = '🟡';
    } else {
      dotColor = Colors.grey;
      rankLabel = '🔴';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: dotColor.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: dotColor.withAlpha(40), width: 0.5),
        ),
        child: Row(
          children: [
            // 排名序号
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: dotColor.withAlpha(30),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: dotColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 线路名
            Expanded(
              child: Text(
                road.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: index == 0 ? FontWeight.w600 : null,
                ),
              ),
            ),
            // 排名标签
            Text(
              rankLabel,
              style: TextStyle(
                color: dotColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/video_source/speed_tester.dart';

/// 测速对话框 — 点击播放时显示，对可用源进行测速和排序
class SpeedTestDialog {
  /// 显示测速对话框，返回排序后的源列表
  ///
  /// [sources] 格式: [{name: '源A', url: 'https://...', ...}]
  /// 返回按速度排序后的 sources
  static Future<List<Map<String, String>>?> show({
    required BuildContext context,
    required List<Map<String, String>> sources,
  }) async {
    if (sources.isEmpty) return sources;

    final completer = Completer<List<Map<String, String>>?>();
    
    await KazumiDialog.show(
      builder: (ctx) => _SpeedTestDialogContent(
        sources: sources,
        onComplete: (sorted) {
          KazumiDialog.dismiss();
          completer.complete(sorted);
        },
      ),
    );

    return completer.future;
  }
}

class _SpeedTestDialogContent extends StatefulWidget {
  final List<Map<String, String>> sources;
  final void Function(List<Map<String, String>>?) onComplete;

  const _SpeedTestDialogContent({
    required this.sources,
    required this.onComplete,
  });

  @override
  State<_SpeedTestDialogContent> createState() =>
      _SpeedTestDialogContentState();
}

class _SpeedTestDialogContentState extends State<_SpeedTestDialogContent> {
  final SpeedTester _tester = SpeedTester();
  List<SourceSpeedResult>? _results;
  bool _testing = true;

  @override
  void initState() {
    super.initState();
    _runTests();
  }

  Future<void> _runTests() async {
    final results = await _tester.testSources(widget.sources);
    if (mounted) {
      setState(() {
        _results = results;
        _testing = false;
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
          Text(_testing ? '正在检测视频源速度...' : '检测完成'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _testing ? _buildTesting(theme) : _buildResults(theme),
      ),
      actions: [
        if (!_testing)
          TextButton(
            onPressed: () => widget.onComplete(_sortedSources()),
            child: const Text('确认并使用最快源'),
          ),
      ],
    );
  }

  Widget _buildTesting(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text('正在测试 ${widget.sources.length} 个视频源...',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text('最快源将自动排在最前面',
            style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_results == null || _results!.isEmpty) {
      return const Text('未获取到可用源');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._results!.map((result) => _buildResultItem(theme, result)),
      ],
    );
  }

  Widget _buildResultItem(ThemeData theme, SourceSpeedResult result) {
    IconData icon;
    Color color;
    String label;

    if (!result.isAvailable) {
      icon = Icons.close_rounded;
      color = Colors.red;
      label = '不可用';
    } else if (result.needsVerification) {
      icon = Icons.warning_rounded;
      color = Colors.orange;
      label = '需要验证';
    } else {
      icon = Icons.check_circle_rounded;
      color = Colors.green;
      label = '${result.latencyMs}ms';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              result.sourceName,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, String>> _sortedSources() {
    if (_results == null) return widget.sources;

    final sorted = List<Map<String, String>>.from(widget.sources);
    sorted.sort((a, b) {
      final ra = _results!.firstWhere(
        (r) => r.sourceUrl == a['url'],
        orElse: () => SourceSpeedResult(
          sourceName: '', sourceUrl: '', latencyMs: 9999,
          isAvailable: false,
        ),
      );
      final rb = _results!.firstWhere(
        (r) => r.sourceUrl == b['url'],
        orElse: () => SourceSpeedResult(
          sourceName: '', sourceUrl: '', latencyMs: 9999,
          isAvailable: false,
        ),
      );
      if (ra.isAvailable != rb.isAvailable) return ra.isAvailable ? -1 : 1;
      if (ra.needsVerification != rb.needsVerification) {
        return ra.needsVerification ? 1 : -1;
      }
      return ra.latencyMs.compareTo(rb.latencyMs);
    });
    return sorted;
  }
}

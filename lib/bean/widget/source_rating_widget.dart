import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/source_rating_service.dart';

/// 🆕 规则源稳定性评分组件
///
/// 展示某播放源的用户评分（稳定性/清晰度/可用性三维聚合），
/// 点击可打分（匿名，限IP，每源每IP一条可更新）。
class SourceRatingWidget extends StatefulWidget {
  final String sourceId;
  const SourceRatingWidget({super.key, required this.sourceId});

  @override
  State<SourceRatingWidget> createState() => _SourceRatingWidgetState();
}

class _SourceRatingWidgetState extends State<SourceRatingWidget> {
  SourceRating? _rating;
  late bool _loading;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // C 策略：列表打开零请求，只用缓存；用户点开评分弹窗时才拉服务器
    _rating = SourceRatingService.cached(widget.sourceId);
    _loading = false;
  }

  /// 打开打分弹窗
  Future<void> _openRateDialog() async {
    // 懒加载：点开评分时才拉最新（无缓存才请求服务器）
    if (_rating == null) {
      final r = await SourceRatingService.fetch(widget.sourceId);
      if (!mounted) return;
      if (r != null) setState(() => _rating = r);
    }
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => _RateDialog(sourceId: widget.sourceId, current: _rating?.my),
    );
    if (result == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      final r = await SourceRatingService.submit(
        sourceId: widget.sourceId,
        stability: result['stability'] ?? 5,
        clarity: result['clarity'] ?? 5,
        usable: result['usable'] ?? 1,
      );
      if (!mounted) return;
      setState(() {
        _rating = r;
        _submitting = false;
      });
      KazumiDialog.showToast(message: '✅ 评分已提交');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      KazumiDialog.showToast(message: '❌ ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final r = _rating;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('评分加载中…', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _submitting ? null : _openRateDialog,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              size: 16,
              color: Colors.amber,
            ),
            const SizedBox(width: 4),
            if (r != null && r.count > 0) ...[
              Text(
                '${r.total.toStringAsFixed(1)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                ' (${r.count}人)',
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
              const SizedBox(width: 6),
              Text(
                '⭐ 我去评分',
                style: TextStyle(fontSize: 11, color: colorScheme.primary),
              ),
            ] else ...[
              Text(
                '暂无评分 · 去评分',
                style: TextStyle(fontSize: 12, color: colorScheme.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 打分弹窗：三维（稳定性=卡不卡 / 清晰度 / 能不能用）
class _RateDialog extends StatefulWidget {
  final String sourceId;
  final MyRating? current;
  const _RateDialog({required this.sourceId, this.current});

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late int _stability;
  late int _clarity;
  late int _usable;

  @override
  void initState() {
    super.initState();
    _stability = widget.current?.stability ?? 5;
    _clarity = widget.current?.clarity ?? 5;
    _usable = widget.current?.usable ?? 1;
  }

  Widget _starRow({
    required String label,
    required IconData icon,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(5, (i) {
            final n = i + 1;
            return InkWell(
              onTap: () => onChanged(n),
              child: Icon(
                n <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                color: n <= value ? Colors.amber : Colors.grey.shade400,
                size: 26,
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('评价播放源：${widget.sourceId}',
          style: const TextStyle(fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _starRow(
              label: '稳定性（卡不卡）',
              icon: Icons.speed_rounded,
              value: _stability,
              onChanged: (v) => setState(() => _stability = v),
            ),
            const SizedBox(height: 12),
            _starRow(
              label: '清晰度',
              icon: Icons.high_quality_rounded,
              value: _clarity,
              onChanged: (v) => setState(() => _clarity = v),
            ),
            const SizedBox(height: 12),
            Text('能不能用',
                style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 1,
                    label: Text('✅ 能用'),
                    icon: Icon(Icons.check_circle_outline, size: 16)),
                ButtonSegment(
                    value: 0,
                    label: Text('❌ 用不了'),
                    icon: Icon(Icons.cancel_outlined, size: 16)),
              ],
              selected: {_usable},
              onSelectionChanged: (s) => setState(() => _usable = s.first),
            ),
            const SizedBox(height: 4),
            Text('匿名评分，每源每设备只能评一次，可修改',
                style: TextStyle(fontSize: 11, color: colorScheme.outline)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop({'stability': _stability, 'clarity': _clarity, 'usable': _usable}),
          child: const Text('提交评分'),
        ),
      ],
    );
  }
}

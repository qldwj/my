import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/navigation.dart';

/// 🆕 AnimeFlow 追番列表卡片（每行一个条目）
///
/// 布局：
/// - 左侧：海报图片（宽高比 2:3，圆角 12px）
/// - 右侧：名称、类型、年份、集数、评分等文字信息
class AnimeFlowCard extends StatelessWidget {
  const AnimeFlowCard({
    super.key,
    required this.bangumiItem,
    this.canTap = true,
    this.onLongPress,
  });

  final BangumiItem bangumiItem;
  final bool canTap;
  final VoidCallback? onLongPress;

  /// 展示用名称（优先中文名）
  String get _title {
    final n = bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;
    return n.isEmpty ? '未知番剧' : n;
  }

  /// 类型文字（取第一个 tag，否则按 type 兜底）
  String get _typeText {
    if (bangumiItem.tags.isNotEmpty && bangumiItem.tags.first.name.isNotEmpty) {
      return bangumiItem.tags.first.name;
    }
    return switch (bangumiItem.type) {
      1 => '动画',
      2 => '书籍',
      3 => '音乐',
      4 => '游戏',
      _ => '动画',
    };
  }

  /// 年份（从 airDate 提取 YYYY）
  String get _yearText {
    final m = RegExp(r'(\d{4})').firstMatch(bangumiItem.airDate);
    if (m != null) return m.group(1)!;
    return '未知';
  }

  /// 集数文字
  String get _episodeText {
    final total = bangumiItem.totalEpisodes;
    if (total > 0) return '$total 集';
    return '集数未知';
  }

  /// 评分文字
  String get _ratingText {
    final score = bangumiItem.ratingScore;
    if (score > 0) return score.toStringAsFixed(1);
    return '暂无';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: InkWell(
        onTap: () {
          if (!canTap) {
            KazumiDialog.showToast(message: '编辑模式');
            return;
          }
          context.pushNamed('/info/', arguments: bangumiItem);
        },
        onLongPress: canTap ? onLongPress : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左：海报 2:3，圆角 12
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 86,
                  height: 129,
                  child: NetworkImgLayer(
                    src: bangumiItem.images['large'] ??
                        bangumiItem.images['common'] ??
                        '',
                    width: 86,
                    height: 129,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 右：文字信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 类型 · 年份 · 集数
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _infoChip(context, _typeText),
                        _infoChip(context, _yearText),
                        _infoChip(context, _episodeText),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 评分
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 16, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text(
                          _ratingText,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            bangumiItem.summary.isNotEmpty
                                ? bangumiItem.summary
                                : '暂无简介',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

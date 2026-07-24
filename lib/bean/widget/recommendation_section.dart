import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 番剧关联推荐组件
///
/// 在番剧详情页底部显示"喜欢这部的人也喜欢…"
/// 基于标签匹配度推荐
class RecommendationSection extends StatelessWidget {
  final BangumiItem currentBangumi;

  const RecommendationSection({
    super.key,
    required this.currentBangumi,
  });

  @override
  Widget build(BuildContext context) {
    final recommendations = _getRecommendations();

    if (recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.recommend_rounded, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '喜欢这部的人也喜欢',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: recommendations.length,
            itemBuilder: (context, index) {
              return SizedBox(
                width: 140,
                child: BangumiCardV(bangumiItem: recommendations[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 基于标签匹配度获取推荐番剧
  List<BangumiItem> _getRecommendations() {
    try {
      // 从收藏中找标签相似的其他番剧
      final currentTags = currentBangumi.tags.map((t) => t.name).toSet();
      if (currentTags.isEmpty) return [];

      final Map<BangumiItem, int> scored = {};

      for (final collectible in GStorage.collectibles.values) {
        final item = collectible.bangumiItem;
        // 排除当前番剧
        if (item.id == currentBangumi.id) continue;

        // 计算标签匹配度
        final itemTags = item.tags.map((t) => t.name).toSet();
        final matches = currentTags.intersection(itemTags).length;
        if (matches > 0) {
          scored[item] = matches;
        }
      }

      // 按匹配度排序，取前10个
      final sorted = scored.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sorted.take(10).map((e) => e.key).toList();
    } catch (_) {
      return [];
    }
  }
}

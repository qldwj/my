import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 续集/关联作品推荐组件
///
/// 在番剧详情页底部显示"续集"和"关联作品"
/// 基于番剧名称关键词（如"第X季""Season X"等）匹配
class RelatedAnimeSection extends StatelessWidget {
  final BangumiItem currentBangumi;

  const RelatedAnimeSection({
    super.key,
    required this.currentBangumi,
  });

  @override
  Widget build(BuildContext context) {
    final related = _getRelatedAnime();

    if (related.isEmpty) {
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
              Icon(Icons.connected_tv_rounded, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '续集 / 关联作品',
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
            itemCount: related.length,
            itemBuilder: (context, index) {
              return SizedBox(
                width: 140,
                child: BangumiCardV(bangumiItem: related[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 从收藏和历史中查找关联作品
  List<BangumiItem> _getRelatedAnime() {
    try {
      final currentName = currentBangumi.nameCn.isNotEmpty
          ? currentBangumi.nameCn
          : currentBangumi.name;
      if (currentName.isEmpty) return [];

      // 提取番剧基础名称（去掉"第X季"等后缀）
      final baseName = _extractBaseName(currentName);
      if (baseName.isEmpty) return [];

      final Map<BangumiItem, double> scored = {};
      final allItems = <BangumiItem>{};

      // 从收藏中收集
      for (final collectible in GStorage.collectibles.values) {
        allItems.add(collectible.bangumiItem);
      }

      for (final item in allItems) {
        if (item.id == currentBangumi.id) continue;
        final itemName = item.nameCn.isNotEmpty ? item.nameCn : item.name;
        if (itemName.contains(baseName) || baseName.contains(itemName)) {
          scored[item] = 1.0;
        }
      }

      final sorted = scored.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return sorted.take(10).map((e) => e.key).toList();
    } catch (e) {
      KazumiLogger().e('RelatedAnime: 获取关联作品失败', error: e);
      return [];
    }
  }

  String _extractBaseName(String name) {
    // 去掉常见的季数后缀
    final cleaned = name
        .replaceAll(RegExp(r'[第][一二三四五六七八九十\d]+[季期部]'), '')
        .replaceAll(RegExp(r'Season\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'S\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'Part\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\（].*?[\)\）]'), '')
        .trim();
    return cleaned;
  }
}

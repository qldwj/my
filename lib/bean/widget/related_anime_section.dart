import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/subject_relation.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';

/// 续集 / 关联作品组件（番剧详情页概览 Tab 底部）
///
/// 与官方 Kazumi 一致：基于 Bangumi API
/// `GET /v0/subjects/{id}/subjects` 获取真实关联条目
/// （续集、前传、衍生、OVA 等），不再用本地关键词猜测。
/// Bangumi 镜像开启时自动走 api.qlyyz.top 镜像后端。
class RelatedAnimeSection extends StatefulWidget {
  final BangumiItem currentBangumi;

  const RelatedAnimeSection({
    super.key,
    required this.currentBangumi,
  });

  @override
  State<RelatedAnimeSection> createState() => _RelatedAnimeSectionState();
}

class _RelatedAnimeSectionState extends State<RelatedAnimeSection> {
  List<SubjectRelation> _related = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list =
        await BangumiApi.getRelatedSubjects(widget.currentBangumi.id);
    if (!mounted) return;
    setState(() {
      _related = list;
      _loading = false;
    });
  }

  /// 将 SubjectRelation 转换为 BangumiItem（复用现有卡片渲染）
  BangumiItem _toBangumiItem(SubjectRelation r) => BangumiItem(
        id: r.id,
        type: r.type,
        name: r.name,
        nameCn: r.nameCn,
        summary: '',
        airDate: '',
        airWeekday: 0,
        rank: 0,
        images: r.images,
        tags: const [],
        alias: const [],
        ratingScore: 0,
        votes: 0,
        votesCount: const [],
        info: r.relation,
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final valid = _related
        .where((r) => r.id != widget.currentBangumi.id)
        .toList();
    if (valid.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.connected_tv_rounded,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '续集 / 关联作品',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: valid.length,
            itemBuilder: (context, index) {
              final bgmItem = _toBangumiItem(valid[index]);
              return SizedBox(
                width: 140,
                child: BangumiCardV(bangumiItem: bgmItem),
              );
            },
          ),
        ),
      ],
    );
  }
}
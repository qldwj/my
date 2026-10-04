import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/apis/recommend_api.dart';

/// 播放页「相关推荐」区块，复用首页推荐接口，横排卡片，点击进入详情页。
class PlayRecommendSection extends StatefulWidget {
  const PlayRecommendSection({super.key});

  @override
  State<PlayRecommendSection> createState() => _PlayRecommendSectionState();
}

class _PlayRecommendSectionState extends State<PlayRecommendSection> {
  final List<BangumiItem> _list = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await RecommendApi.fetchRecommendations(offset: 0, limit: 12);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.list.isEmpty) {
        _error = '暂无相关推荐';
      } else {
        _list.addAll(r.list);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(
                  '相关推荐',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  onPressed: _load,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (_loading && _list.isEmpty)
            const SizedBox(
              height: 130,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_list.isEmpty)
            SizedBox(
              height: 130,
              child: Center(
                child: Text(
                  _error ?? '暂无内容',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) => _PlayRecCard(item: _list[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayRecCard extends StatelessWidget {
  const _PlayRecCard({required this.item});

  final BangumiItem item;

  @override
  Widget build(BuildContext context) {
    final name = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    return InkWell(
      onTap: () => context.pushNamed('/info/', arguments: item),
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: NetworkImgLayer(
                src: item.images['large'] ?? '',
                width: 96,
                height: 134,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/apis/recommend_api.dart';

/// 首页顶部横排「为你推荐」区块，点击进入详情页
class RecommendSection extends StatefulWidget {
  const RecommendSection({super.key});

  @override
  State<RecommendSection> createState() => _RecommendSectionState();
}

class _RecommendSectionState extends State<RecommendSection> {
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
    final r = await RecommendApi.fetchRecommendations(offset: 0, limit: 20);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.list.isEmpty) {
        _error = '暂无推荐';
      } else {
        _list.addAll(r.list);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // ⭐ 紧贴顶部标题栏：去掉上方空隙
      padding: const EdgeInsets.only(top: 0, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '为你推荐',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: _load,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (_loading && _list.isEmpty)
            const SizedBox(
              height: 150,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_list.isEmpty)
            SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  _error ?? '暂无内容',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            )
          else
            SizedBox(
              height: 178,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) => _RecCard(item: _list[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecCard extends StatelessWidget {
  const _RecCard({required this.item});

  final BangumiItem item;

  @override
  Widget build(BuildContext context) {
    final name = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    return InkWell(
      onTap: () => context.pushNamed('/info/', arguments: item),
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 104,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: NetworkImgLayer(
                src: item.images['large'] ?? '',
                width: 104,
                height: 144,
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

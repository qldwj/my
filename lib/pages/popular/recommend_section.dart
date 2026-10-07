import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/card/network_img_layer.dart';
import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/request/apis/recommend_api.dart';

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
    // 🔴 缓存优先：进程内 → Hive → 无缓存才请求（冷启动重新访问，不退出不重复拉）
    final memory = RecommendApi.memoryCache();
    if (memory != null && memory.isNotEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _list..clear()..addAll(memory);
      });
      return;
    }
    final cached = RecommendApi.cachedItems();
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _list..clear()..addAll(cached);
      });
      // Hive 缓存直达后，冷启动才重新访问网络（会话内已加载过则不再请求）
      if (!RecommendApi.loadedThisSession) {
        _refreshFromNetwork();
      }
      return;
    }
    // 无缓存：骨架屏占位 + 请求
    setState(() {
      _loading = true;
      _error = null;
    });
    await _refreshFromNetwork();
  }

  Future<void> _refreshFromNetwork() async {
    final r = await RecommendApi.fetchRecommendations(offset: 0, limit: 20);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.list.isEmpty) {
        _error = '暂无推荐';
      } else {
        _list..clear()..addAll(r.list);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
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
            // 🔴 骨架屏：无网络/未解析时先展示占位卡片，解析后填真实内容
            SizedBox(
              height: 178,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: 5,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) => const _RecSkeletonCard(),
              ),
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

/// 骨架屏占位卡片（加载中/无网络时先显示）
class _RecSkeletonCard extends StatelessWidget {
  const _RecSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fill = colors.surfaceContainerHighest;
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 104,
            height: 144,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: 90,
            height: 12,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 60,
            height: 12,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

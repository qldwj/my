import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/apis/recommend_api.dart';

/// 独立底部 tab「为你推荐」：代理 Animeko 官方推荐，竖向无限分页
class RecommendPage extends StatefulWidget {
  const RecommendPage({super.key});

  @override
  State<RecommendPage> createState() => _RecommendPageState();
}

class _RecommendPageState extends State<RecommendPage> {
  final List<BangumiItem> _list = [];
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 300) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await RecommendApi.fetchRecommendations(
      offset: _list.length,
      limit: 20,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.list.isEmpty) {
        _hasMore = false;
        if (_list.isEmpty) _error = '暂时没有推荐内容';
      } else {
        _list.addAll(r.list);
        _hasMore = r.hasMore;
      }
    });
  }

  Future<void> _refresh() async {
    _list.clear();
    _hasMore = true;
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('为你推荐'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_list.isEmpty) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return ListView(
        children: [
          const SizedBox(height: 160),
          Center(
            child: Text(
              _error ?? '暂无内容',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _loadMore,
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _list.length + 1,
      itemBuilder: (context, index) {
        if (index >= _list.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_hasMore
                    ? const SizedBox.shrink()
                    : Center(
                        child: Text(
                          '没有更多了',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      )),
          );
        }
        return _RecommendTile(item: _list[index]);
      },
    );
  }
}

class _RecommendTile extends StatelessWidget {
  const _RecommendTile({required this.item});

  final BangumiItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    final sub = <String>[
      if (item.airDate.isNotEmpty) item.airDate,
      if (item.summary.isNotEmpty) item.summary,
    ].join('  ');
    return InkWell(
      onTap: () => context.pushNamed('/info/', arguments: item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: NetworkImgLayer(
                src: item.images['large'] ?? '',
                width: 90,
                height: 126,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: cs.outlineVariant, size: 20),
          ],
        ),
      ),
    );
  }
}

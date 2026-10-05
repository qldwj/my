import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/card/network_img_layer.dart';
import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/request/apis/recommend_api.dart';

/// 首页顶部横排「为你推荐」区块，点击进入详情页
/// - 缓存直达：有本地缓存时首帧直接渲染内容，后台静默刷新（不闪加载）
/// - 骨架屏：无缓存首次加载时显示占位卡片，加载完成后内容淡入浮现
/// - 横向无限滚动：滑到末尾自动加载下一页；网络失败保留继续加载能力
class RecommendSection extends StatefulWidget {
  const RecommendSection({super.key});

  @override
  State<RecommendSection> createState() => _RecommendSectionState();
}

class _RecommendSectionState extends State<RecommendSection> {
  final List<BangumiItem> _list = [];
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  bool _hasMore = true;
  bool _loadingMore = false;
  String? _error;
  DateTime _lastFail = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 首帧：优先缓存直达（不闪骨架），无缓存才走骨架 + 网络
  Future<void> _load() async {
    final cached = RecommendApi.cachedItems();
    if (cached != null) {
      setState(() {
        _loading = false;
        _error = null;
        _list
          ..clear()
          ..addAll(cached);
        _hasMore = cached.length < RecommendApi.serverTotal;
      });
      _refresh(); // 后台静默刷新，成功后内容自动补位
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
      _list.clear();
    });
    final r = await RecommendApi.fetchRecommendations(offset: 0);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.list.isEmpty) {
        _error = r.ok ? '暂无推荐' : '网络异常，请下拉重试';
      } else {
        _list.addAll(r.list);
      }
      _hasMore = r.ok && r.hasMore;
    });
  }

  /// 后台静默刷新：成功后内容浮现补位
  Future<void> _refresh() async {
    final r = await RecommendApi.fetchRecommendations(offset: 0);
    if (!mounted || !r.ok) return;
    setState(() {
      _list
        ..clear()
        ..addAll(r.list);
      _hasMore = r.hasMore;
    });
  }

  /// 横向滑到接近末尾时自动加载下一页，实现一直往右滑
  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    // 网络/风控失败冷却 10 秒，避免连续请求触发服务器人机验证
    if (DateTime.now().difference(_lastFail).inSeconds < 10) return;
    setState(() => _loadingMore = true);
    final r = await RecommendApi.fetchRecommendations(offset: _list.length);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (!r.ok) {
        _lastFail = DateTime.now(); // 失败不终止加载，冷却后滑动可重试
        return;
      }
      _hasMore = r.hasMore;
      _list.addAll(r.list);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 顶部留 4px 间距，紧贴热门番组标题栏；底部微留间距
      padding: const EdgeInsets.only(top: 4, bottom: 2),
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
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  /// 骨架屏 → 内容 → 空态，切换时淡入浮现
  Widget _buildBody() {
    if (_loading && _list.isEmpty) {
      return const _SkeletonRow(key: ValueKey('skeleton'));
    }
    if (_list.isEmpty) {
      return SizedBox(
        key: const ValueKey('empty'),
        height: 150,
        child: Center(
          child: Text(
            _error ?? '暂无内容',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      );
    }
    return SizedBox(
      key: const ValueKey('content'),
      height: 178,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) => _RecCard(item: _list[i]),
      ),
    );
  }
}

/// 加载骨架：一排粉色占位卡片，轻微脉动，加载完成淡出
class _SkeletonRow extends StatefulWidget {
  const _SkeletonRow({super.key});

  @override
  State<_SkeletonRow> createState() => _SkeletonRowState();
}

class _SkeletonRowState extends State<_SkeletonRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.95).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: SizedBox(
        height: 178,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: 8,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, __) => const _SkeletonCard(),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final block = cs.surfaceContainerHighest.withOpacity(0.55);
    final line = cs.surfaceContainerHighest.withOpacity(0.9);
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 104,
              height: 144,
              color: block,
            ),
          ),
          const SizedBox(height: 8),
          Container(width: 68, height: 10, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(5))),
          const SizedBox(height: 5),
          Container(width: 88, height: 10, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(5))),
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

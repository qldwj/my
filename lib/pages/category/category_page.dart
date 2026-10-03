import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/pages/category/category_api.dart';
import 'package:kazumi/utils/constants.dart';

/// 次元城分类页：顶部分类切换 + 标签/年份筛选 + 视频网格（分页 + 下拉刷新）
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  bool _loadingZones = true;
  bool _loading = false;
  bool _error = false;

  List<CategoryZone> _zones = [];
  int _zoneId = 0;
  String _category = '';
  int _year = 0;

  final List<CategoryVideo> _videos = [];
  int _page = 1;
  bool _hasMore = true;
  int _openingVideoId = 0;

  static const int _pageSize = 24;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 300) {
      if (!_loading && _hasMore) {
        _loadVideos(reset: false);
      }
    }
  }

  Future<void> _init() async {
    setState(() {
      _loadingZones = true;
      _error = false;
    });
    final zones = await CategoryApi.fetchZones();
    if (!mounted) return;
    if (zones.isEmpty) {
      setState(() {
        _loadingZones = false;
        _error = true;
      });
      return;
    }
    setState(() {
      _zones = zones;
      _zoneId = zones.first.id;
      _loadingZones = false;
    });
    await _loadVideos(reset: true);
  }

  Future<void> _loadVideos({required bool reset}) async {
    if (_zoneId == 0) return;
    if (reset) {
      _page = 1;
      _hasMore = true;
      _videos.clear();
    }
    setState(() => _loading = true);
    final list = await CategoryApi.fetchVideos(
      zoneId: _zoneId,
      category: _category,
      year: _year,
      page: _page,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      if (list.isEmpty) {
        _hasMore = false;
      } else {
        _videos.addAll(list);
        _page++;
      }
      _loading = false;
    });
  }

  Future<void> _onRefresh() async {
    await _loadVideos(reset: true);
  }

  void _changeZone(CategoryZone zone) {
    if (zone.id == _zoneId) return;
    setState(() {
      _zoneId = zone.id;
      _category = '';
      _year = 0;
    });
    _loadVideos(reset: true);
  }

  void _changeCategory(String c) {
    if (c == _category) return;
    setState(() => _category = c);
    _loadVideos(reset: true);
  }

  void _changeYear(int y) {
    if (y == _year) return;
    setState(() => _year = y);
    _loadVideos(reset: true);
  }

  /// 点击分类视频 → 取真实 bangumi_id → 跳转现有 Bangumi 详情页
  Future<void> _openDetail(CategoryVideo video) async {
    if (_openingVideoId != 0) return;
    setState(() => _openingVideoId = video.videoId);
    final det = await CategoryApi.fetchVideoDetail(video.videoId);
    if (!mounted) return;
    setState(() => _openingVideoId = 0);
    if (det == null || det.bangumiId <= 0) {
      KazumiDialog.showToast(message: '该视频暂无法获取详情');
      return;
    }
    final item = BangumiItem(
      id: det.bangumiId,
      type: 2,
      name: det.title,
      nameCn: det.title,
      summary: det.description,
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {
        'large': det.coverUrl,
        'medium': det.coverUrl,
        'small': det.coverUrl,
      },
      tags: const <BangumiTag>[],
      alias: const <String>[],
      ratingScore: det.score,
      votes: 0,
      votesCount: const <int>[],
      info: '',
    );
    context.pushNamed('/info/', arguments: item);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loadingZones) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error) {
      return Scaffold(
        appBar: AppBar(title: const Text('分类')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('分类加载失败，请检查网络后重试'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _init, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            centerTitle: false,
            title: const Text('分类'),
            backgroundColor: Theme.of(context).colorScheme.surface,
          ),
          SliverToBoxAdapter(child: _buildFilters()),
          if (_loading) ..._loadingIndicators(),
          _videos.isEmpty && !_loading
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: _loading ? null : const Text('该筛选条件下暂无内容'),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _crossCount(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      mainAxisExtent:
                          MediaQuery.sizeOf(context).width / _crossCount() / 0.7 +
                              36,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final v = _videos[index];
                        return _CategoryCard(
                          video: v,
                          onTap: () => _openDetail(v),
                          opening: _openingVideoId == v.videoId,
                        );
                      },
                      childCount: _videos.length,
                    ),
                  ),
                ),
        ],
      ),
    ),
  );
  }

  List<Widget> _loadingIndicators() {
    return const [
      SliverToBoxAdapter(
        child: LinearProgressIndicator(minHeight: 2),
      ),
    ];
  }

  int _crossCount() {
    final w = MediaQuery.sizeOf(context).width;
    if (w > LayoutBreakpoint.medium['width']!) return 5;
    if (w > LayoutBreakpoint.compact['width']!) return 4;
    return 3;
  }

  Widget _buildFilters() {
    final zone = _currentZone();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分类切换
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final z in _zones)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(z.name),
                      selected: z.id == _zoneId,
                      onSelected: (_) => _changeZone(z),
                    ),
                  ),
              ],
            ),
          ),
          if (zone != null && zone.categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            _chipRow(
              items: ['', ...zone.categories],
              selected: _category,
              labelOf: (c) => c.isEmpty ? '全部' : c,
              onSelect: _changeCategory,
            ),
          ],
          if (zone != null && zone.years.isNotEmpty) ...[
            const SizedBox(height: 4),
            _chipRow(
              items: [0, ...zone.years.map(int.parse).toList()],
              selected: _year,
              labelOf: (y) => y == 0 ? '全部年份' : '$y',
              onSelect: _changeYear,
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipRow<T>({
    required List<T> items,
    required T selected,
    required String Function(T) labelOf,
    required ValueChanged<T> onSelect,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(labelOf(it)),
                selected: it == selected,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onSelect(it),
              ),
            ),
        ],
      ),
    );
  }

  CategoryZone? _currentZone() {
    for (final z in _zones) {
      if (z.id == _zoneId) return z;
    }
    return _zones.isEmpty ? null : _zones.first;
  }
}

/// 分类视频卡片
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.video,
    required this.onTap,
    this.opening = false,
  });

  final CategoryVideo video;
  final VoidCallback onTap;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 0.7,
                  child: NetworkImgLayer(
                    src: video.coverUrl,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(5, 3, 5, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12.5,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${video.year > 0 ? video.year : ''}${video.score > 0 ? '  ·  评分 ${video.score}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (opening)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

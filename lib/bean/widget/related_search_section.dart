import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/nsfw_filter.dart';

/// 智能关联搜索 Tab
///
/// 根据当前番剧名称自动提取关键词：
/// 如「海绵宝宝 第四季」→ 自动提取「海绵宝宝」进行搜索，
/// 支持多关键词切换，点击结果卡片跳转到对应详情页。
class RelatedSearchSection extends StatefulWidget {
  final BangumiItem currentBangumi;

  const RelatedSearchSection({
    super.key,
    required this.currentBangumi,
  });

  @override
  State<RelatedSearchSection> createState() => _RelatedSearchSectionState();
}

class _RelatedSearchSectionState extends State<RelatedSearchSection> {
  List<String> _keywords = [];
  String _currentKeyword = '';
  List<BangumiItem> _results = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _keywords = _deriveKeywords(widget.currentBangumi);
    _autoSearch();
  }

  /// 智能关键词提取：
  /// 优先基础名（去掉"第X季/Season X/S\d+/Part X"等后缀），
  /// 再补充完整中文名、英文名，按顺序排列。
  List<String> _deriveKeywords(BangumiItem item) {
    final ordered = <String>[];
    void add(String? n) {
      final s = n?.trim() ?? '';
      if (s.isEmpty || s.length < 2) return;
      if (!ordered.contains(s)) ordered.add(s);
    }

    final cn = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    final baseCn = _extractBaseName(cn);
    final en = item.nameCn.isNotEmpty ? item.name : '';
    final baseEn = _extractBaseName(en);

    add(baseCn); // 海绵宝宝
    add(cn); // 海绵宝宝 第四季
    add(item.nameCn);
    add(baseEn); // SpongeBob
    add(en); // SpongeBob SquarePants
    return ordered;
  }

  /// 去掉番剧名称中的季数/副标题后缀
  String _extractBaseName(String name) {
    if (name.isEmpty) return '';
    return name
        .replaceAll(RegExp(r'[第][一二三四五六七八九十\d]+[季期部]'), '')
        .replaceAll(RegExp(r'Season\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'S\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'Part\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\\(（].*?[\\)）]'), '')
        .trim();
  }

  /// 智能自动搜索：按关键词顺序逐个尝试，直到有结果为止
  Future<void> _autoSearch() async {
    for (final kw in _keywords) {
      if (!mounted) return;
      setState(() {
        _currentKeyword = kw;
        _loading = true;
        _error = null;
      });
      final items = await _doSearch(kw);
      if (!mounted) return;
      if (items.isNotEmpty) {
        setState(() {
          _results = items;
          _loading = false;
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _results = [];
      _error = '没有找到相关作品，可以点上方关键词手动搜索';
    });
  }

  /// 用户点击关键词手动搜索
  Future<void> _searchKeyword(String keyword) async {
    if (keyword == _currentKeyword && _results.isNotEmpty) return;
    setState(() {
      _currentKeyword = keyword;
      _loading = true;
      _error = null;
    });
    final items = await _doSearch(keyword);
    if (!mounted) return;
    setState(() {
      _results = items;
      _loading = false;
    });
  }

  Future<List<BangumiItem>> _doSearch(String keyword) async {
    try {
      final page = await BangumiApi.bangumiSearch(
        keyword,
        limit: 20,
        sort: 'heat',
      );
      final items = (page?.items ?? [])
          .where((e) => e.id != widget.currentBangumi.id)
          .where((e) => !NsfwFilter.isNsfw(e))
          .toList();
      return items;
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Builder(
      builder: (context) {
        return CustomScrollView(
          scrollBehavior: const ScrollBehavior().copyWith(
            scrollbars: false,
          ),
          key: const PageStorageKey<String>('相关搜索'),
          slivers: <Widget>[
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '关联搜索',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '自动提取关键词搜索，点击结果跳转详情',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_keywords.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final kw in _keywords)
                            ChoiceChip(
                              label: Text(
                                kw,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: kw == _currentKeyword,
                              onSelected: (_) => _searchKeyword(kw),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_results.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(_error ?? '什么都没有找到 (´;ω;`)'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 8,
                    crossAxisCount: _crossCount(context),
                    mainAxisExtent:
                        MediaQuery.sizeOf(context).width /
                                _crossCount(context) /
                                0.65 +
                            MediaQuery.textScalerOf(context).scale(32.0),
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => BangumiCardV(
                      enableHero: false,
                      bangumiItem: _results[index],
                    ),
                    childCount: _results.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  int _crossCount(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w > LayoutBreakpoint.medium['width']!) return 6;
    if (w > LayoutBreakpoint.compact['width']!) return 5;
    return 3;
  }
}

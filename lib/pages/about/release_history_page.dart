import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/pages/about/about_widgets.dart';
import 'package:yhdm/request/config/api_endpoints.dart';

/// 🆕 版本历史 / 更新日志页
///
/// - 数据源：**镜像优先**（[ApiEndpoints.allAppReleasesMirror]），
///   镜像失败时自动回退 GitHub（[ApiEndpoints.allAppReleases]）。
/// - 默认展示 10 条，往下滚动到底自动加载下一页。
/// - 最新版本默认展开，其余折叠。
/// - 每条右下角有 GitHub 图标，点击跳转该版本的仓库 Release 页。
class ReleaseHistoryPage extends StatefulWidget {
  const ReleaseHistoryPage({super.key});

  @override
  State<ReleaseHistoryPage> createState() => _ReleaseHistoryPageState();
}

class _ReleaseHistoryPageState extends State<ReleaseHistoryPage> {
  static const int _pageSize = 10;

  final _scrollController = ScrollController();
  final List<_ReleaseItem> _items = [];
  final Set<String> _expanded = {}; // 已展开的 tag

  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // 距底部 300px 内触发加载下一页
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await _fetchPage(_page);
      if (!mounted) return;
      setState(() {
        final seen = _items.map((e) => e.tag).toSet();
        for (final r in list) {
          if (!seen.contains(r.tag)) _items.add(r);
        }
        // 第一页时默认展开最新版本
        if (_page == 1 && _items.isNotEmpty) {
          _expanded.add(_items.first.tag);
        }
        _page++;
        _hasMore = list.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 拉取第 [page] 页（每页 [_pageSize] 条），镜像优先、GitHub 兜底
  Future<List<_ReleaseItem>> _fetchPage(int page) async {
    final skip = (page - 1) * _pageSize;

    // ① 镜像（国内快）
    try {
      final raw = await _getPlain(ApiEndpoints.allAppReleasesMirror);
      final decoded = json.decode(raw);
      if (decoded is List) {
        final all = _parseList(decoded);
        if (all.isNotEmpty) {
          final slice = skip >= all.length
              ? <_ReleaseItem>[]
              : all.skip(skip).take(_pageSize).toList();
          return slice;
        }
      }
    } catch (_) {
      // 镜像失败 → 走 GitHub
    }

    // ② GitHub 兜底（分页用 page/per_page）
    final raw = await _getPlain(
      '${ApiEndpoints.allAppReleases}&page=$page&per_page=$_pageSize',
    );
    final decoded = json.decode(raw);
    if (decoded is List) return _parseList(decoded);
    return const [];
  }

  Future<String> _getPlain(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close();
      final body = await res.transform(const Utf8Decoder()).join();
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  List<_ReleaseItem> _parseList(List data) {
    final out = <_ReleaseItem>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      if (raw['draft'] == true) continue;
      final tag = (raw['tag_name'] as String?) ?? '';
      if (tag.isEmpty) continue;
      final name = (raw['name'] as String?)?.trim() ?? '';
      out.add(
        _ReleaseItem(
          tag: tag,
          title: name.isNotEmpty ? name : tag,
          body: (raw['body'] as String?) ?? '',
          url: (raw['html_url'] as String?) ?? '',
          publishedAt: (raw['published_at'] as String?) ?? '',
          prerelease: raw['prerelease'] == true,
          apkSize: _apkSizeOf(raw['assets']),
        ),
      );
    }
    return out;
  }

  String _apkSizeOf(dynamic assets) {
    if (assets is! List) return '';
    for (final a in assets) {
      if (a is Map && (a['name'] as String?)?.toLowerCase().endsWith('.apk') == true) {
        final size = a['size'];
        if (size is int && size > 0) {
          return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
        }
      }
    }
    return '';
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: const Text('更新日志')),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12))),
                  TextButton(
                    onPressed: _loadMore,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _items.clear();
                  _expanded.clear();
                  _page = 1;
                  _hasMore = true;
                });
                await _loadMore();
              },
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                itemCount: _items.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _items.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: _loading
                            ? const CircularProgressIndicator()
                            : const SizedBox.shrink(),
                      ),
                    );
                  }
                  return _buildTile(context, _items[index]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(BuildContext context, _ReleaseItem item) {
    final cs = Theme.of(context).colorScheme;
    final isOpen = _expanded.contains(item.tag);
    final date = _formatDate(item.publishedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (!isOpen) {
                _expanded.add(item.tag);
              } else {
                _expanded.remove(item.tag);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (item.prerelease) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '测试版',
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    isOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // 🆕 展开/收起使用高度动画（AnimatedSize），不再是瞬间显示
          AnimatedSize(
            duration: Duration(milliseconds: isOpen ? 240 : 180),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: isOpen ? 1.0 : 0.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              if (item.body.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    item.body.trim(),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              const Divider(height: 1),
              // 底部信息条：日期 / 大小 / 右下角 GitHub 图标
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                child: Row(
                  children: [
                    if (date.isNotEmpty)
                      Text(date,
                          style: TextStyle(fontSize: 12, color: cs.outline)),
                    if (date.isNotEmpty && item.apkSize.isNotEmpty)
                      Text(' · ', style: TextStyle(color: cs.outline)),
                    if (item.apkSize.isNotEmpty)
                      Text(item.apkSize,
                          style: TextStyle(fontSize: 12, color: cs.outline)),
                    const Spacer(),
                    IconButton(
                      tooltip: '在 GitHub 打开',
                      visualDensity: VisualDensity.compact,
                      onPressed: item.url.isEmpty
                          ? null
                          : () => openAboutLink(context, item.url),
                      icon: Icon(Icons.code_rounded,
                          size: 20, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseItem {
  const _ReleaseItem({
    required this.tag,
    required this.title,
    required this.body,
    required this.url,
    required this.publishedAt,
    required this.prerelease,
    required this.apkSize,
  });

  final String tag;
  final String title;
  final String body;
  final String url;
  final String publishedAt;
  final bool prerelease;
  final String apkSize;
}
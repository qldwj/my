import 'package:flutter/material.dart';
import 'package:kazumi/models/episode_comment.dart';
import 'package:kazumi/services/comment/episode_comment_service.dart';
import 'package:kazumi/widgets/comment/comment_item.dart';
import 'package:kazumi/widgets/comment/comment_editor.dart';

class CommentListPage extends StatefulWidget {
  final int subjectId;
  final String animeName;
  const CommentListPage({super.key, required this.subjectId, required this.animeName});
  @override
  State<CommentListPage> createState() => _CommentListPageState();
}

class _CommentListPageState extends State<CommentListPage> {
  List<EpisodeComment> _comments = [];
  bool _loading = true;
  String _sort = 'time';
  int _selectedEpisode = 0;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() => _loading = true);
    _comments = await EpisodeCommentService.getComments(
      subjectId: widget.subjectId,
      episode: _selectedEpisode,
      sort: _sort,
    );
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('评论 · ${widget.animeName}'),
        actions: [
          // 排序选择
          PopupMenuButton<String>(
            onSelected: (v) { setState(() => _sort = v); _loadComments(); },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'time', child: Text('最新')),
              const PopupMenuItem(value: 'likes', child: Text('最热')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_sort == 'time' ? Icons.access_time : Icons.trending_up, size: 18),
                const SizedBox(width: 4),
                Text(_sort == 'time' ? '最新' : '最热', style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 集数选择
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _episodeChip('条目', 0),
                for (int i = 1; i <= 24; i++) _episodeChip('第$i集', i),
              ],
            ),
          ),
          const Divider(height: 1),
          // 评论列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? const Center(child: Text('暂无评论', style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _loadComments,
                        child: ListView.builder(
                          itemCount: _comments.length,
                          itemBuilder: (ctx, i) => CommentItemWidget(
                            comment: _comments[i],
                            subjectId: widget.subjectId,
                            onRefresh: _loadComments,
                          ),
                        ),
                      ),
          ),
          // 评论输入框
          CommentEditor(
            subjectId: widget.subjectId,
            episode: _selectedEpisode,
            onSubmitted: _loadComments,
          ),
        ],
      ),
    );
  }

  Widget _episodeChip(String label, int episode) {
    final selected = _selectedEpisode == episode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : null)),
        selected: selected,
        onSelected: (v) { setState(() => _selectedEpisode = episode); _loadComments(); },
        selectedColor: Theme.of(context).colorScheme.primary,
        checkmarkColor: Colors.white,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

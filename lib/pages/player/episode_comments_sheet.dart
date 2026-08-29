import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/models/episode_comment.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/comments/comment_item.dart' show EpisodeCommentItem;
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/comment/episode_comment_service.dart';
import 'package:kazumi/widgets/comment/comment_editor.dart';
import 'package:kazumi/widgets/comment/comment_item.dart';

/// 播放页评论 Tab（樱花动漫评论系统）
///
/// - 列表：读取樱花动漫评论（当前集数）
/// - 底部：评论输入框，自动匹配当前观看集数
class EpisodeCommentsSheet extends StatefulWidget {
  const EpisodeCommentsSheet({
    super.key,
    required this.videoPageController,
    required this.episode,
    required this.selection,
  });

  final VideoPageController videoPageController;
  final int episode;
  final VideoEpisodeSelection selection;

  @override
  State<EpisodeCommentsSheet> createState() => _EpisodeCommentsSheetState();
}

class _EpisodeCommentsSheetState extends State<EpisodeCommentsSheet> {
  VideoPageController get videoPageController => widget.videoPageController;
  List<EpisodeComment> _comments = [];
  bool _loading = true;
  bool _error = false;
  int _episode = 0;

  @override
  void initState() {
    super.initState();
    _episode = widget.episode;
    _loadComments();
  }

  @override
  void didUpdateWidget(covariant EpisodeCommentsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode != widget.episode ||
        oldWidget.selection != widget.selection) {
      _episode = widget.episode;
      _loadComments();
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      // 1. 加载樱花动漫评论
      final sakuraComments = await EpisodeCommentService.getComments(
        subjectId: videoPageController.bangumiItem.id,
        episode: _episode,
      );
      // 2. 加载 Bangumi 评论（结果存到 episodeCommentsList）
      bool bangumiLoaded = false;
      try {
        bangumiLoaded = await videoPageController.queryBangumiEpisodeCommentsByID(
          videoPageController.bangumiItem.id,
          _episode,
        );
      } catch (_) {
        // Bangumi 评论加载失败不影响樱花评论
      }

      if (!mounted) return;

      // 合并列表：樱花在前，Bangumi 在后
      final merged = <EpisodeComment>[];
      // 樱花评论（已自带 source='sakura'）
      merged.addAll(sakuraComments);
      // Bangumi 评论（转成 EpisodeComment 格式）
      if (bangumiLoaded) {
        for (final item in videoPageController.episodeCommentsList) {
          merged.add(EpisodeComment(
            id: item.comment.id,
            subjectId: videoPageController.bangumiItem.id,
            episode: _episode,
            content: item.comment.comment,
            sender: item.comment.user.nickname,
            uid: 'bangumi_${item.comment.user.id}',
            avatar: item.comment.user.avatar.large,
            source: 'bangumi',
            createdAt: item.comment.createdAt,
            replies: item.replies.map((r) => EpisodeComment(
              id: r.id,
              content: r.comment,
              sender: r.user.nickname,
              uid: 'bangumi_${r.user.id}',
              avatar: r.user.avatar.large,
              source: 'bangumi',
              createdAt: r.createdAt,
            )).toList(),
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _comments = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _showEpisodeSelection() async {
    final int selectedEpisode = _episode == 0 ? widget.episode : _episode;
    KazumiDialog.showLoading(msg: '分集列表加载中');
    final List<EpisodeInfo> episodeList =
        await BangumiApi.getBangumiEpisodesByID(
            videoPageController.bangumiItem.id);
    KazumiDialog.dismiss();
    if (!mounted) {
      return;
    }
    if (episodeList.isEmpty) {
      KazumiDialog.showToast(message: '未找到分集列表');
      return;
    }
    KazumiDialog.show(
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text('分集列表', style: TextStyle(fontSize: 20)),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: episodeList.length,
                    itemBuilder: (context, index) {
                      final episode = episodeList[index];
                      final episodeTitle = episode.nameCn.isNotEmpty
                          ? episode.nameCn
                          : episode.name;
                      final episodeText = '${episode.readType()}.${episode.episode}';
                      final bool selected = index + 1 == selectedEpisode;
                      return ListTile(
                        selected: selected,
                        title: Text(
                          episodeTitle.isEmpty
                              ? episodeText
                              : '$episodeText $episodeTitle',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          _episode = index + 1;
                          _loadComments();
                          KazumiDialog.dismiss();
                        },
                      );
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: TextButton(
                      onPressed: () => KazumiDialog.dismiss(),
                      child: Text(
                        '取消',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 切换集数（手动选择）
  void _switchEpisode(int ep) {
    if (ep == _episode) return;
    setState(() => _episode = ep);
    _loadComments();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部信息：当前集数 + 切换按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    videoPageController.episodeInfo.nameCn.isNotEmpty
                        ? '第${_episode == 0 ? widget.episode : _episode}集 '
                            '${videoPageController.episodeInfo.nameCn}'
                        : '第${_episode == 0 ? widget.episode : _episode}集',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(
                        const EdgeInsets.only(left: 4.0, right: 4.0)),
                  ),
                  onPressed: _showEpisodeSelection,
                  child: const Text('手动切换', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 评论列表（樱花动漫评论）
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('评论加载失败',
                                style: TextStyle(color: cs.outline)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _loadComments,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : _comments.isEmpty
                        ? const Center(
                            child: Text('还没有评论，来抢沙发吧 (´;ω;`)',
                                style: TextStyle(color: Colors.grey)),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadComments,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 8),
                              itemCount: _comments.length,
                              itemBuilder: (ctx, i) => CommentItemWidget(
                                comment: _comments[i],
                                subjectId: videoPageController.bangumiItem.id,
                                onRefresh: _loadComments,
                              ),
                            ),
                          ),
          ),
          // 底部评论输入框（自动匹配当前集）
          CommentEditor(
            subjectId: videoPageController.bangumiItem.id,
            episode: _episode == 0 ? widget.episode : _episode,
            onSubmitted: _loadComments,
          ),
        ],
      ),
    );
  }
}
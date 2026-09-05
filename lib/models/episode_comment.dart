class EpisodeComment {
  final int id;
  final int subjectId;
  final int episode;
  final int parentId;
  final String content;
  final String sender;
  final String uid;
  final String avatar;
  final String source;
  final int likes;
  final int dislikes;
  final int replyCount;
  final int createdAt;
  final List<EpisodeComment> replies;
  final List<CommentReaction> reactions;

  EpisodeComment({
    required this.id,
    required this.subjectId,
    this.episode = 0,
    this.parentId = 0,
    required this.content,
    this.sender = '',
    this.uid = '',
    this.avatar = '',
    this.source = 'sakura',
    this.likes = 0,
    this.dislikes = 0,
    this.replyCount = 0,
    required this.createdAt,
    this.replies = const [],
    this.reactions = const [],
  });

  factory EpisodeComment.fromJson(Map<String, dynamic> json) {
    return EpisodeComment(
      id: json['id'] ?? 0,
      subjectId: json['subject_id'] ?? 0,
      episode: json['episode'] ?? 0,
      parentId: json['parent_id'] ?? 0,
      content: json['content'] ?? '',
      sender: json['sender'] ?? '',
      uid: json['uid'] ?? '',
      avatar: json['avatar'] ?? '',
      source: json['source'] ?? 'sakura',
      likes: json['likes'] ?? 0,
      dislikes: json['dislikes'] ?? 0,
      replyCount: json['reply_count'] ?? 0,
      createdAt: json['created_at'] ?? 0,
      replies: (json['replies'] as List?)?.map((e) => EpisodeComment.fromJson(e)).toList() ?? [],
      reactions: (json['reactions'] as List?)?.map((e) => CommentReaction.fromJson(e)).toList() ?? [],
    );
  }

  bool get isSakura => source == 'sakura';
  bool get isBangumi => source == 'bangumi';
  String get timeAgo {
    final diff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - createdAt;
    if (diff < 60) return '刚刚';
    if (diff < 3600) return '${diff ~/ 60}分钟前';
    if (diff < 86400) return '${diff ~/ 3600}小时前';
    if (diff < 604800) return '${diff ~/ 86400}天前';
    return '${diff ~/ 604800}周前';
  }
}

class CommentReaction {
  final String sticker;
  final int count;
  CommentReaction({required this.sticker, this.count = 0});
  factory CommentReaction.fromJson(Map<String, dynamic> json) {
    return CommentReaction(sticker: json['sticker'] ?? '', count: json['count'] ?? 0);
  }
}

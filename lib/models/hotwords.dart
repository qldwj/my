// models/hotwords.dart
class HotWord {
  final String word;
  final int count;

  HotWord({required this.word, required this.count});

  factory HotWord.fromJson(Map<String, dynamic> json) {
    return HotWord(
      word: json['word'] as String,
      count: json['count'] as int,
    );
  }
}

class HotwordsResponse {
  final int episodeId;
  final String animeTitle;
  final List<HotWord> hotwords;
  final int totalDanmaku;

  HotwordsResponse({
    required this.episodeId,
    required this.animeTitle,
    required this.hotwords,
    required this.totalDanmaku,
  });

  factory HotwordsResponse.fromJson(Map<String, dynamic> json) {
    return HotwordsResponse(
      episodeId: json['episode_id'] as int,
      animeTitle: json['anime_title'] as String? ?? '',
      hotwords: (json['hotwords'] as List<dynamic>? ?? []).map((e) => HotWord.fromJson(e)).toList(),
      totalDanmaku: json['total_danmaku'] as int? ?? 0,
    );
  }
}

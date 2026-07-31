// models/anime.dart
import 'dart:convert';

class ScheduleItem {
  final int animeId;
  final String title;
  final int episode;
  final String broadcastTime;
  final int countdown; // seconds or minutes as backend provides

  ScheduleItem({
    required this.animeId,
    required this.title,
    required this.episode,
    required this.broadcastTime,
    required this.countdown,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    return ScheduleItem(
      animeId: json['anime_id'] as int,
      title: json['title'] as String,
      episode: json['episode'] as int,
      broadcastTime: json['broadcast_time'] as String,
      countdown: (json['countdown'] is int) ? json['countdown'] as int : int.parse(json['countdown'].toString()),
    );
  }
}

class RandomAnimeResult {
  final int id;
  final String title;
  final String coverUrl;
  final String synopsis;
  final String source;

  RandomAnimeResult({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.synopsis,
    required this.source,
  });

  factory RandomAnimeResult.fromJson(Map<String, dynamic> json) {
    final anime = json['anime'] ?? {};
    return RandomAnimeResult(
      id: anime['id'] as int,
      title: anime['title'] as String,
      coverUrl: anime['cover_url'] as String? ?? '',
      synopsis: anime['synopsis'] as String? ?? '',
      source: json['source'] as String? ?? '',
    );
  }
}

class ColdAnime {
  final int id;
  final String title;
  final double rating;
  final int rank;
  final int viewCount;
  final String coverUrl;
  final List<String> tags;
  final String reason;

  ColdAnime({
    required this.id,
    required this.title,
    required this.rating,
    required this.rank,
    required this.viewCount,
    required this.coverUrl,
    required this.tags,
    required this.reason,
  });

  factory ColdAnime.fromJson(Map<String, dynamic> json) {
    return ColdAnime(
      id: json['id'] as int,
      title: json['title'] as String,
      rating: (json['rating'] is num) ? (json['rating'] as num).toDouble() : double.parse(json['rating'].toString()),
      rank: json['rank'] as int? ?? 0,
      viewCount: json['view_count'] as int? ?? 0,
      coverUrl: json['cover_url'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      reason: json['reason'] as String? ?? '',
    );
  }
}

class RecommendationItem {
  final int id;
  final String title;
  final String coverUrl;
  final double matchRate;
  final String reason;

  RecommendationItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.matchRate,
    required this.reason,
  });

  factory RecommendationItem.fromJson(Map<String, dynamic> json) {
    return RecommendationItem(
      id: json['id'] as int,
      title: json['title'] as String,
      coverUrl: json['cover_url'] as String? ?? '',
      matchRate: (json['match_rate'] is num) ? (json['match_rate'] as num).toDouble() : double.parse(json['match_rate'].toString()),
      reason: json['reason'] as String? ?? '',
    );
  }
}

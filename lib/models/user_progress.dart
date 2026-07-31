// models/user_progress.dart
class ProgressDetail {
  final int animeId;
  final String title;
  final int watchedEpisodes;
  final int totalEpisodes;
  final String status;

  ProgressDetail({
    required this.animeId,
    required this.title,
    required this.watchedEpisodes,
    required this.totalEpisodes,
    required this.status,
  });

  factory ProgressDetail.fromJson(Map<String, dynamic> json) {
    return ProgressDetail(
      animeId: json['anime_id'] as int,
      title: json['title'] as String,
      watchedEpisodes: json['watched_episodes'] as int,
      totalEpisodes: json['total_episodes'] as int,
      status: json['status'] as String? ?? '',
    );
  }
}

class UserProgress {
  final int watched;
  final int total;
  final double percentage;
  final String message;
  final List<ProgressDetail> details;

  UserProgress({
    required this.watched,
    required this.total,
    required this.percentage,
    required this.message,
    required this.details,
  });

  factory UserProgress.fromJson(Map<String, dynamic> json) {
    return UserProgress(
      watched: json['watched'] as int,
      total: json['total'] as int,
      percentage: (json['percentage'] is num) ? (json['percentage'] as num).toDouble() : double.parse(json['percentage'].toString()),
      message: json['message'] as String? ?? '',
      details: (json['details'] as List<dynamic>? ?? []).map((e) => ProgressDetail.fromJson(e)).toList(),
    );
  }
}

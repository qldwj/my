import 'package:kazumi/modules/bangumi/bangumi_item.dart';

/// 播放列表中的一项（无 Hive 注解，由 PlaylistService 做 JSON 持久化）
class PlaylistItem {
  final BangumiItem bangumiItem;
  final String adapterName;
  final int episodeNumber;
  final String episodeTitle;
  final String src;
  final int road;
  final DateTime addedTime;

  PlaylistItem({
    required this.bangumiItem,
    required this.adapterName,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.src,
    required this.road,
    required this.addedTime,
  });

  Map<String, dynamic> toJson() => {
        'bangumi_id': bangumiItem.id,
        'bangumi_name': bangumiItem.name,
        'bangumi_name_cn': bangumiItem.nameCn,
        'bangumi_summary': bangumiItem.summary,
        'bangumi_images': bangumiItem.images,
        'bangumi_rating': bangumiItem.ratingScore,
        'adapter_name': adapterName,
        'episode_number': episodeNumber,
        'episode_title': episodeTitle,
        'src': src,
        'road': road,
        'added_time': addedTime.toIso8601String(),
      };

  static BangumiItem _bangumiFromJson(Map<String, dynamic> json) {
    return BangumiItem(
      id: json['bangumi_id'] as int,
      name: json['bangumi_name'] as String? ?? '',
      nameCn: json['bangumi_name_cn'] as String? ?? '',
      summary: json['bangumi_summary'] as String? ?? '',
      images: (json['bangumi_images'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
      tags: [],
      alias: [],
      ratingScore: (json['bangumi_rating'] as num?)?.toDouble() ?? 0.0,
      type: 0,
      airDate: '',
      airWeekday: 0,
      rank: 0,
      votes: 0,
      votesCount: [],
      info: '',
    );
  }

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      bangumiItem: _bangumiFromJson(json),
      adapterName: json['adapter_name'] as String? ?? '',
      episodeNumber: json['episode_number'] as int? ?? 0,
      episodeTitle: json['episode_title'] as String? ?? '',
      src: json['src'] as String? ?? '',
      road: json['road'] as int? ?? 0,
      addedTime: DateTime.tryParse(json['added_time'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// 播放列表
class Playlist {
  final String id;
  String name;
  final DateTime createdTime;
  DateTime updatedTime;

  Playlist({
    required this.id,
    required this.name,
    required this.createdTime,
    required this.updatedTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_time': createdTime.toIso8601String(),
        'updated_time': updatedTime.toIso8601String(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      createdTime: DateTime.tryParse(json['created_time'] as String? ?? '') ??
          DateTime.now(),
      updatedTime: DateTime.tryParse(json['updated_time'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

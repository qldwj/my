import 'package:kazumi/modules/bangumi/bangumi_item.dart';

class TopItem {
  final int id;
  final String name;
  final String nameCn;
  final int type;
  final String time;
  final String image;
  final String summary;
  final double rating;

  TopItem({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.type,
    required this.time,
    required this.image,
    required this.summary,
    required this.rating,
  });

  factory TopItem.fromJson(Map<String, dynamic> json) {
    return TopItem(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      nameCn: json['name_cn'] ?? '',
      type: json['type'] ?? 0,
      time: json['time'] ?? '',
      image: json['image'] ?? '',
      summary: json['summary'] ?? '',
      rating: (json['rating'] ?? 0).toDouble(),
    );
  }

  // 转换为 BangumiItem，用于跳转到详情页
  BangumiItem toBangumiItem() {
    return BangumiItem.fromJson({
      'id': id,
      'type': type,
      'name': name,
      'name_cn': nameCn,
      'summary': summary,
      'date': time,
      'images': {
        'large': image,
        'medium': image,
        'small': image,
        'grid': image,
        'common': image,
      },
      'tags': [],
      'rating': {
        'rank': 0,
        'score': rating,
        'total': 0,
        'count': <int>[],
      },
      'info': '',
      'eps': 0,
    });
  }
}
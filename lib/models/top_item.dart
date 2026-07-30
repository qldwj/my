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
}
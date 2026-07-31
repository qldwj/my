// models/marker.dart
class Marker {
  final int id;
  final double position; // 0.0 - 1.0 as fraction of progress
  final String text;
  final String userId;

  Marker({
    required this.id,
    required this.position,
    required this.text,
    required this.userId,
  });

  factory Marker.fromJson(Map<String, dynamic> json) {
    return Marker(
      id: json['id'] as int,
      position: (json['position'] is num) ? (json['position'] as num).toDouble() : double.parse(json['position'].toString()),
      text: json['text'] as String? ?? '',
      userId: json['user_id']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'position': position,
      'text': text,
    };
  }
}

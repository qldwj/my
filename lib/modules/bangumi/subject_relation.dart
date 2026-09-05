/// 条目的关联条目（续集/前传/衍生等）
///
/// 对应 Bangumi API `GET /v0/subjects/{subject_id}/subjects` 返回结构。
class SubjectRelation {
  final int id;
  final int type;
  final String name;
  final String nameCn;
  final String relation;
  final Map<String, String> images;

  SubjectRelation({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.relation,
    required this.images,
  });

  factory SubjectRelation.fromJson(Map<String, dynamic> json) {
    return SubjectRelation(
      id: json['id'] as int? ?? 0,
      type: json['type'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      nameCn: json['name_cn'] as String? ?? '',
      relation: json['relation'] as String? ?? '',
      images: (json['images'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
    );
  }
}

// models/personality.dart
class PersonalityTag {
  final String currentTag;
  final String description;
  final bool changedToday;
  final List<String> allTags;

  PersonalityTag({
    required this.currentTag,
    required this.description,
    required this.changedToday,
    required this.allTags,
  });

  factory PersonalityTag.fromJson(Map<String, dynamic> json) {
    return PersonalityTag(
      currentTag: json['current_tag'] as String? ?? '',
      description: json['description'] as String? ?? '',
      changedToday: json['changed_today'] as bool? ?? false,
      allTags: (json['all_tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

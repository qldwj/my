// widgets/personality_banner.dart
import 'package:flutter/material.dart';
import '../models/personality.dart';
import '../services/user_service.dart';
import '../services/api_client.dart';

class PersonalityBanner extends StatefulWidget {
  const PersonalityBanner({Key? key}) : super(key: key);

  @override
  State<PersonalityBanner> createState() => _PersonalityBannerState();
}

class _PersonalityBannerState extends State<PersonalityBanner> {
  final UserService _service = UserService(ApiClient());
  PersonalityTag? _tag;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await _service.fetchPersonality();
      setState(() {
        _tag = t;
        _loading = false;
      });
      if (t.changedToday) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('追番人格已变化为：${t.currentTag}')));
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_tag == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.person, color: Colors.teal),
        title: Text(_tag!.currentTag, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(_tag!.description),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {},
          itemBuilder: (ctx) => _tag!.allTags.map((t) => PopupMenuItem(value: t, child: Text(t))).toList(),
        ),
      ),
    );
  }
}

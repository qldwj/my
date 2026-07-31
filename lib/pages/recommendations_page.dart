// pages/recommendations_page.dart
import 'package:flutter/material.dart';
import '../services/recommend_service.dart';
import '../services/api_client.dart';
import '../widgets/recommendations_list.dart';
import '../models/anime.dart';

class RecommendationsPage extends StatefulWidget {
  const RecommendationsPage({Key? key}) : super(key: key);

  @override
  State<RecommendationsPage> createState() => _RecommendationsPageState();
}

class _RecommendationsPageState extends State<RecommendationsPage> {
  final RecommendService _service = RecommendService(ApiClient());
  List<RecommendationItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final recs = await _service.fetchSimilarRecommendations();
      setState(() {
        _items = recs;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('协同推荐')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RecommendationsList(items: _items),
    );
  }
}

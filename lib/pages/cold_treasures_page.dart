// pages/cold_treasures_page.dart
import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/anime_service.dart';
import '../services/api_client.dart';

class ColdTreasuresPage extends StatefulWidget {
  const ColdTreasuresPage({Key? key}) : super(key: key);

  @override
  State<ColdTreasuresPage> createState() => _ColdTreasuresPageState();
}

class _ColdTreasuresPageState extends State<ColdTreasuresPage> {
  final AnimeService _service = AnimeService(ApiClient());
  List<ColdAnime> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _service.fetchColdList();
      setState(() {
        _list = (res['list'] as List<ColdAnime>);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('冷门宝藏专区')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _list.length,
              itemBuilder: (c, i) {
                final a = _list[i];
                return ListTile(
                  leading: Image.network(a.coverUrl, width: 72, height: 96, fit: BoxFit.cover),
                  title: Text(a.title),
                  subtitle: Text('评分 ${a.rating} · 热度 ${a.viewCount} · ${a.tags.join('、')}'),
                  trailing: const Icon(Icons.chevron_right),
                );
              },
            ),
    );
  }
}

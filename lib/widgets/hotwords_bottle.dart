// widgets/hotwords_bottle.dart
import 'package:flutter/material.dart';
import '../models/hotwords.dart';
import '../services/danmaku_service.dart';
import '../services/api_client.dart';

class HotwordsBottle extends StatefulWidget {
  final int episodeId;
  const HotwordsBottle({Key? key, required this.episodeId}) : super(key: key);

  @override
  State<HotwordsBottle> createState() => _HotwordsBottleState();
}

class _HotwordsBottleState extends State<HotwordsBottle> {
  final DanmakuService _service = DanmakuService(ApiClient());
  HotwordsResponse? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final d = await _service.fetchHotwords(widget.episodeId);
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_data == null) return const SizedBox.shrink();
    final top3 = _data!.hotwords.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.black.withOpacity(0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('本集热词 Top 3 — ${_data!.animeTitle}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: top3.map((w) => Column(children: [
              Text(w.word, style: const TextStyle(color: Colors.white, fontSize: 16)),
              Text('${w.count} 条', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])).toList(),
          ),
        ],
      ),
    );
  }
}

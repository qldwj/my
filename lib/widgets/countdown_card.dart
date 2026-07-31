// widgets/countdown_card.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/anime_service.dart';
import '../services/api_client.dart';

class CountdownCard extends StatefulWidget {
  const CountdownCard({Key? key}) : super(key: key);

  @override
  State<CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<CountdownCard> {
  Timer? _timer;
  List<ScheduleItem> _schedule = [];
  Duration? _nextCountdown;
  String _label = '';

  final AnimeService _service = AnimeService(ApiClient());

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final schedule = await _service.fetchCalendar();
      setState(() {
        _schedule = schedule;
      });
      _updateNext();
    } catch (e) {
      // ignore
    }
  }

  void _updateNext() {
    if (_schedule.isEmpty) {
      setState(() {
        _label = '暂无即将放送';
      });
      return;
    }
    final first = _schedule.first;
    // 假设 countdown 是秒数
    final seconds = first.countdown;
    final dur = Duration(seconds: seconds);
    final hours = dur.inHours;
    final minutes = dur.inMinutes.remainder(60);
    setState(() {
      _nextCountdown = dur;
      _label = '${hours}小时${minutes}分后播出';
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.schedule, color: Colors.deepPurple),
        title: Text(_label, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: _schedule.isEmpty
            ? const Text('暂无资料')
            : Text('${_schedule.first.title} 第${_schedule.first.episode}话 • ${_schedule.first.broadcastTime}'),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _load(),
        ),
      ),
    );
  }
}

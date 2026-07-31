// widgets/progress_week_bar.dart
import 'package:flutter/material.dart';
import '../models/user_progress.dart';
import '../services/user_service.dart';
import '../services/api_client.dart';

class ProgressWeekBar extends StatefulWidget {
  const ProgressWeekBar({Key? key}) : super(key: key);

  @override
  State<ProgressWeekBar> createState() => _ProgressWeekBarState();
}

class _ProgressWeekBarState extends State<ProgressWeekBar> {
  final UserService _service = UserService(ApiClient());
  UserProgress? _progress;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _service.fetchProgress();
      setState(() {
        _progress = p;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 56, child: Center(child: CircularProgressIndicator()));
    if (_progress == null) return const SizedBox.shrink();
    final pct = (_progress!.total == 0) ? 0.0 : (_progress!.watched / _progress!.total);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('本周追番进度 ${_progress!.watched}/${_progress!.total}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: pct, minHeight: 8),
        if (_progress!.message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_progress!.message, style: const TextStyle(color: Colors.grey))),
      ]),
    );
  }
}

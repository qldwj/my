// widgets/dice_blindbox.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/anime_service.dart';
import '../services/api_client.dart';

class DiceBlindbox extends StatefulWidget {
  const DiceBlindbox({Key? key}) : super(key: key);

  @override
  State<DiceBlindbox> createState() => _DiceBlindboxState();
}

class _DiceBlindboxState extends State<DiceBlindbox> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  RandomAnimeResult? _result;
  bool _isRolling = false;
  final AnimeService _service = AnimeService(ApiClient());

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _ctrl.reset();
        _showResult();
      }
    });
  }

  Future<void> _roll() async {
    if (_isRolling) return;
    setState(() => _isRolling = true);
    _ctrl.forward();
    try {
      final res = await _service.fetchRandom();
      _result = res;
    } catch (e) {
      _result = null;
    } finally {
      setState(() => _isRolling = false);
    }
  }

  void _showResult() {
    showModalBottomSheet(
      context: context,
      builder: (c) {
        if (_result == null) {
          return SizedBox(height: 180, child: Center(child: Text('未能获取盲盒结果')));
        }
        final r = _result!;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Image.network(r.coverUrl, width: 80, height: 110, fit: BoxFit.cover),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(r.synopsis, maxLines: 4, overflow: TextOverflow.ellipsis),
                ])),
              ]),
              const SizedBox(height: 12),
              Text('来源: ${r.source}', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: _roll,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final angle = _ctrl.value * pi * 2;
            return Transform.rotate(
              angle: angle,
              child: child,
            );
          },
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Icon(Icons.casino, size: 36, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

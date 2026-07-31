// widgets/marker_button.dart
import 'package:flutter/material.dart';
import '../models/marker.dart';
import '../services/marker_service.dart';
import '../services/api_client.dart';

typedef OnCreateMarker = Future<void> Function(Marker marker);

class MarkerButton extends StatelessWidget {
  final int episodeId;
  final Future<List<Marker>> Function() loadMarkers;
  final OnCreateMarker onCreate;

  const MarkerButton({
    Key? key,
    required this.episodeId,
    required this.loadMarkers,
    required this.onCreate,
  }) : super(key: key);

  Future<void> _showAddDialog(BuildContext context) async {
    final posController = TextEditingController(text: '0.5');
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('添加名场面标记'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: posController,
              decoration: const InputDecoration(labelText: '位置(0.0 - 1.0)'),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                if (d == null || d < 0 || d > 1) return '请输入 0 到 1 之间的数字';
                return null;
              },
            ),
            TextFormField(
              controller: textController,
              decoration: const InputDecoration(labelText: '文本'),
              validator: (v) => (v == null || v.isEmpty) ? '请输入文本' : null,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          TextButton(onPressed: () {
            if (formKey.currentState!.validate()) Navigator.of(c).pop(true);
          }, child: const Text('添加')),
        ],
      ),
    );
    if (result == true) {
      final pos = double.parse(posController.text);
      final text = textController.text;
      final marker = Marker(id: 0, position: pos, text: text, userId: '');
      await onCreate(marker);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('标记已添加')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.bookmark_add_outlined),
      tooltip: '添加名场面标记',
      onPressed: () => _showAddDialog(context),
    );
  }
}

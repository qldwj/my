// widgets/recommendations_list.dart
import 'package:flutter/material.dart';
import '../models/anime.dart';

class RecommendationsList extends StatelessWidget {
  final List<RecommendationItem> items;

  const RecommendationsList({Key? key, required this.items}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('暂无推荐'));
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (c, i) {
        final it = items[i];
        return ListTile(
          leading: Image.network(it.coverUrl, width: 56, height: 80, fit: BoxFit.cover),
          title: Text(it.title),
          subtitle: Text('匹配度 ${(it.matchRate * 100).toStringAsFixed(0)}% — ${it.reason}'),
        );
      },
    );
  }
}

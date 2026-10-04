import 'package:flutter/material.dart';
import 'package:kazumi/services/level_service.dart';

/// 个人中心等级面板：等级图标 + Lv + 经验条，点击弹出等级详情（经验规则 + 徽章）
class LevelPanel extends StatefulWidget {
  const LevelPanel({super.key});

  @override
  State<LevelPanel> createState() => _LevelPanelState();
}

class _LevelPanelState extends State<LevelPanel> {
  LevelInfo? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await LevelService.fetch();
    if (mounted) setState(() {
      _info = info;
      _loading = false;
    });
  }

  void _showDetail() {
    final info = _info;
    if (info == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _LevelDetailSheet(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 12);
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: _showDetail,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.secondaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  LevelService.levelIconUrl(info.level),
                  width: 26,
                  height: 26,
                  errorBuilder: (_, __, ___) => Text('Lv${info.level}',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: cs.onSecondaryContainer)),
                ),
              ),
              const SizedBox(width: 8),
              Text('Lv${info.level}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: cs.onSecondaryContainer)),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (info.progress / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(info.isMax ? 'MAX' : '${info.exp}/${info.next}',
                  style: TextStyle(fontSize: 11, color: cs.onSecondaryContainer)),
              const Icon(Icons.chevron_right, size: 18, color: cs.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 等级详情：经验规则 + 徽章
class _LevelDetailSheet extends StatelessWidget {
  final LevelInfo info;
  const _LevelDetailSheet({required this.info});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (ctx, sc) => SingleChildScrollView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(LevelService.levelIconUrl(info.level),
                      width: 44, height: 44,
                      errorBuilder: (_, __, ___) => const SizedBox()),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('等级 Lv${info.level}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('累计经验 ${info.exp} 点',
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _section('经验获取', [
              '✅ 每日签到 +20 经验',
              '✅ 每看完一集番剧 +10 经验（每日上限 30）',
              '✅ 发布吐槽/评论 +5 经验（每日上限 20）',
            ]),
            const SizedBox(height: 12),
            _section('升级所需累计经验', [
              'Lv1 → Lv2：20    Lv2 → Lv3：150',
              'Lv3 → Lv4：450    Lv4 → Lv5：1080',
              'Lv5 → Lv6：2880',
            ]),
            const SizedBox(height: 14),
            Text('我的徽章',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.95),
              itemCount: info.badges.length,
              itemBuilder: (_, i) {
                final b = info.badges[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  decoration: BoxDecoration(
                    color: b.unlocked ? cs.primaryContainer.withValues(alpha: 0.55) : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: b.unlocked ? Border.all(color: cs.primary, width: 1) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(opacity: b.unlocked ? 1 : 0.35,
                          child: Text(b.icon, style: const TextStyle(fontSize: 26))),
                      const SizedBox(height: 4),
                      Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                              color: b.unlocked ? cs.onSurface : cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(b.unlocked ? '已解锁' : '未解锁',
                          style: TextStyle(fontSize: 10, color: b.unlocked ? cs.primary : cs.outline)),
                      const SizedBox(height: 2),
                      Text(b.desc, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<String> lines) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines
                .map((l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(l, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

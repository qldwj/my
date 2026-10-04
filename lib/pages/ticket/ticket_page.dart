import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/ticket_service.dart';

/// 番剧纠错工单页
class TicketPage extends StatefulWidget {
  final int subjectId;
  final String subjectName;
  const TicketPage({super.key, this.subjectId = 0, this.subjectName = ''});

  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('番剧纠错工单'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: cs.primary,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: const [Tab(text: '提交工单'), Tab(text: '我的工单')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _SubmitTab(subjectId: widget.subjectId, subjectName: widget.subjectName),
          const _MyTab(),
        ],
      ),
    );
  }
}

/// 提交工单
class _SubmitTab extends StatefulWidget {
  final int subjectId;
  final String subjectName;
  const _SubmitTab({this.subjectId = 0, this.subjectName = ''});

  @override
  State<_SubmitTab> createState() => _SubmitTabState();
}

class _SubmitTabState extends State<_SubmitTab> {
  final _content = TextEditingController();
  final _subject = TextEditingController();
  final _ep = TextEditingController();
  String _type = 'source_fail';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.subjectName.isNotEmpty) _subject.text = widget.subjectName;
  }

  @override
  void dispose() {
    _content.dispose();
    _subject.dispose();
    _ep.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_content.text.trim().isEmpty) {
      KazumiDialog.showToast(message: '请填写问题描述');
      return;
    }
    setState(() => _submitting = true);
    final res = await TicketService.add(
      type: _type,
      content: _content.text.trim(),
      subjectId: widget.subjectId,
      subjectName: _subject.text.trim(),
      ep: _ep.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res['success'] == true) {
      KazumiDialog.showToast(message: '工单已提交，感谢反馈 🙏');
      _content.clear();
      _ep.clear();
    } else {
      KazumiDialog.showToast(message: '提交失败：${res['error'] ?? '未知错误'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('遇到源失效、缺集、字幕或画质问题？提交工单，管理员会尽快处理。',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        // 类型
        Text('问题类型', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: TicketService.types.map((t) => ChoiceChip(
            label: Text(t.name),
            selected: _type == t.id,
            onSelected: (_) => setState(() => _type = t.id),
          )).toList(),
        ),
        const SizedBox(height: 14),
        Text('番剧名称', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: _subject,
          decoration: InputDecoration(hintText: '输入番剧名称（可选）', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
        const SizedBox(height: 12),
        Text('集数', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: _ep,
          decoration: InputDecoration(hintText: '如：第 3 集（可选）', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
        const SizedBox(height: 12),
        Text('问题描述', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: _content,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(hintText: '详细描述遇到的问题…', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? '提交中…' : '提交工单'),
          ),
        ),
      ],
    );
  }
}

/// 我的工单列表
class _MyTab extends StatefulWidget {
  const _MyTab();
  @override
  State<_MyTab> createState() => _MyTabState();
}

class _MyTabState extends State<_MyTab> {
  List<Ticket> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await TicketService.my();
    if (mounted) setState(() {
      _list = list;
      _loading = false;
    });
  }

  Color _statusColor(String s, ColorScheme cs) {
    switch (s) {
      case 'done': return const Color(0xFF2E7D32);
      case 'processing': return const Color(0xFF1565C0);
      case 'rejected': return const Color(0xFFC62828);
      default: return cs.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_list.isEmpty) return Center(child: Text('暂无工单', style: TextStyle(color: cs.onSurfaceVariant)));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _list.length,
        itemBuilder: (_, i) {
          final t = _list[i];
          final color = _statusColor(t.status, cs);
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(6)),
                      child: Text(t.typeName.isEmpty ? t.type : t.typeName,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text(t.statusName,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                    ),
                  ]),
                  if (t.subjectName.isNotEmpty || t.ep.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('${t.subjectName}${t.ep.isNotEmpty ? ' · $t.ep' : ''}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 6),
                  Text(t.content, style: const TextStyle(fontSize: 13, height: 1.4)),
                  const SizedBox(height: 8),
                  Text(t.timeAgo, style: TextStyle(fontSize: 11, color: cs.outline)),
                  if (t.adminReply.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                      child: Text('👨‍💻 管理员：${t.adminReply}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

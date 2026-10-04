import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/pages/my/my_controller.dart';

class DanmakuShieldEditor extends StatefulWidget {
  const DanmakuShieldEditor({
    super.key,
    required this.controller,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 24),
  });

  final MyController controller;
  final EdgeInsetsGeometry padding;

  @override
  State<DanmakuShieldEditor> createState() => _DanmakuShieldEditorState();
}

class _DanmakuShieldEditorState extends State<DanmakuShieldEditor> {
  MyController get myController => widget.controller;
  final TextEditingController textEditingController = TextEditingController();

  @override
  void dispose() {
    textEditingController.dispose();
    super.dispose();
  }

  Future<void> _addRule() async {
    final rule = textEditingController.text.trim();
    if (rule.isEmpty) return;
    final added = await myController.addShieldList(rule);
    if (mounted && added && textEditingController.text.trim() == rule) {
      textEditingController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: widget.padding,
      children: [
        ContentSection(
          title: l10n.setBAddRule,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: textEditingController,
              decoration: InputDecoration(
                hintText: l10n.setBKeywordOrRegex,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                suffixIcon: IconButton(
                  tooltip: l10n.setBAddRule,
                  onPressed: _addRule,
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
              onSubmitted: (_) => _addRule(),
            ),
            const SizedBox(height: 8),
            Text(l10n.setBAddRuleHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ]),
        ),
        const SizedBox(height: 24),
        Observer(builder: (context) {
          final rules = myController.shieldList.toList();
          if (rules.isEmpty) {
            return GeneralEmptyState(
              icon: Icons.filter_alt_off_rounded,
              title: l10n.setBNoRulesYet,
              compact: true,
            );
          }
          return ContentSection.group(
            title: l10n.setBAddedCount(count: rules.length),
            children: [
              for (final rule in rules)
                ListTile(
                  title: Text(rule),
                  subtitle: rule.startsWith('/') && rule.endsWith('/')
                      ? Text(l10n.setBRegexLabel)
                      : null,
                  trailing: IconButton(
                    tooltip: l10n.setBDeleteRule,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => myController.removeShieldList(rule),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}

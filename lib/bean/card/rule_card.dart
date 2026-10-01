import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/source_rating_widget.dart';

/// Rounded tonal card for a rule entry, shared by the rule manage page,
/// the rule shop page and the onboarding rule step.
///
/// 视觉采用官方 2.3.7 重设计（动画容器 + 前导图标块 + 响应式堆叠 + trailing 焦点隔离），
/// 同时保留 my 自定义的稳定性评分槽位（[ratingSourceId] 非空时在 tags 行渲染
/// [SourceRatingWidget]）。
class RuleCard extends StatelessWidget {
  const RuleCard({
    super.key,
    required this.title,
    this.tags = const [],
    this.caption,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.installed = false,
    this.ratingSourceId,
  });

  final String title;
  final List<Widget> tags;

  /// Plain text shown after [tags], e.g. the last update date.
  final String? caption;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool installed;

  /// 非空则在卡片上显示该源的稳定性评分（点击可打分）
  final String? ratingSourceId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Keep menu focus from activating the enclosing InkWell's highlight.
    final actions = trailing == null
        ? null
        : Focus(
            parentNode: Focus.maybeOf(context, scopeOk: true),
            canRequestFocus: false,
            skipTraversal: true,
            child: trailing!,
          );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeInOutCubicEmphasized,
          decoration: BoxDecoration(
            color: selected
                ? colors.secondaryContainer
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(selected ? 20 : 28),
            border: Border.all(
              color: selected ? colors.secondary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(selected ? 18 : 26),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: LayoutBuilder(builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20;
                  final identity = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: duration,
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: selected || installed
                              ? colors.secondaryContainer
                              : colors.primaryContainer,
                          borderRadius:
                              BorderRadius.circular(installed ? 24 : 16),
                        ),
                        child: Icon(
                          selected
                              ? Icons.check_rounded
                              : Icons.extension_rounded,
                          color: selected || installed
                              ? colors.onSecondaryContainer
                              : colors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: text.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            if (subtitle != null && subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant)),
                            ],
                            if (tags.isNotEmpty || ratingSourceId != null) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ...tags,
                                  if (ratingSourceId != null)
                                    SourceRatingWidget(
                                        sourceId: ratingSourceId!),
                                ],
                              ),
                            ],
                            if (caption != null) ...[
                              const SizedBox(height: 6),
                              Text(caption!,
                                  style: text.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        identity,
                        if (actions != null) ...[
                          const SizedBox(height: 8),
                          Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: actions),
                        ],
                      ],
                    );
                  }
                  return Row(children: [
                    Expanded(child: identity),
                    if (actions != null) ...[
                      const SizedBox(width: 12),
                      actions
                    ],
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed-width tonal action button for [RuleCard] trailing slots, so the
/// button edge stays aligned across rows regardless of label length
/// (e.g. 安装 / 更新 / 已安装). Pass null [onPressed] for the disabled state.
class RuleCardActionButton extends StatelessWidget {
  const RuleCardActionButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: FilledButton.tonal(
        onPressed: onPressed,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Small tonal label used inside [RuleCard], e.g. version or captcha tags.
class RuleTag extends StatelessWidget {
  const RuleTag({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

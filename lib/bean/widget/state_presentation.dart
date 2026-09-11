import 'package:flutter/material.dart';

/// 状态操作按钮（Tonal风格）
class StateActionButton extends StatelessWidget {
  const StateActionButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
  });

  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;

  const StateActionButton.tonal({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton.tonal(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 6),
          ],
          Text(text),
        ],
      ),
    );
  }
}

/// 空状态展示
class GeneralEmptyState extends StatelessWidget {
  const GeneralEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actions,
  });

  final IconData icon;
  final String title;
  final String? description;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: colors.outlineVariant),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: colors.onSurface)),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(description!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant)),
            ],
            if (actions != null) ...[
              const SizedBox(height: 24),
              Wrap(spacing: 8, runSpacing: 8, children: actions!),
            ],
          ],
        ),
      ),
    );
  }
}

/// 加载状态展示
class LoadingStatePresentation extends StatelessWidget {
  const LoadingStatePresentation({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

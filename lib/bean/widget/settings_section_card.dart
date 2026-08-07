import 'package:flutter/material.dart';

/// 设置页/我的页通用的分组卡片
class SettingsSectionCard extends StatelessWidget {
  final String? title;
  final Widget? leading;
  final List<Widget> children;

  const SettingsSectionCard({
    super.key,
    this.title,
    this.leading,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontFamily = theme.textTheme.bodyMedium?.fontFamily;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 8)],
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// 通用设置条目
class SettingsEntryTile extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? description;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const SettingsEntryTile({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.description,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontFamily = theme.textTheme.bodyMedium?.fontFamily;
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      leading: leading ??
          (icon != null
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 22, color: theme.colorScheme.primary),
                )
              : null),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: fontFamily)),
      subtitle: description != null
          ? Text(description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: fontFamily))
          : null,
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right, color: theme.colorScheme.outline)
              : null),
    );
  }
}

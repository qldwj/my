import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:yhdm/services/plugin/plugin_icon_cache.dart';

/// Rounded tonal card for a rule entry, shared by the rule manage page,
/// the rule shop page and the onboarding rule step.
///
/// 视觉采用官方 2.3.7 重设计（动画容器 + 前导图标块 + 响应式堆叠 + trailing 焦点隔离）。
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
    this.iconUrl,
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

  /// 该规则的动漫图标 URL（Hive 永久缓存）。为空或加载失败时显示默认图标。
  final String? iconUrl;

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
                          // 白底：透明底 logo 显示白色，有背景色的 logo 由图片 cover 铺满
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(installed ? 24 : 16),
                        ),
                        child: _RuleIcon(
                          url: iconUrl,
                          fallback: Icon(
                            selected
                                ? Icons.check_rounded
                                : Icons.extension_rounded,
                            color: colors.primary,
                          ),
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
                            if (tags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ...tags,
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

/// 规则图标：首次从 [PluginIconCache] 下载并写入 Hive 永久缓存，
/// 之后（含重启）直接读 Hive。无 URL / 加载失败时显示默认 [fallback] 图标。
class _RuleIcon extends StatefulWidget {
  final String? url;
  final Widget fallback;
  const _RuleIcon({required this.url, required this.fallback});

  @override
  State<_RuleIcon> createState() => _RuleIconState();
}

class _RuleIconState extends State<_RuleIcon> {
  Uint8List? _bytes;

  /// 当前 State 正在显示 / 正在加载的 URL。
  /// 列表过滤（已安装/可更新/搜索）后 ListView 会在同一位置复用本 State，
  /// 若只靠 initState 加载，就会把上一张图留在屏幕上（图片不跟着换的根因）。
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _RuleIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // URL 变化 -> 必须换图；清掉旧字节避免闪现上一张
    if (oldWidget.url != widget.url) {
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    _currentUrl = url;
    // URL 为空：立刻回到默认占位，不能继续显示上一张图
    if (url == null || url.isEmpty) {
      if (mounted && _bytes != null) {
        setState(() => _bytes = null);
      }
      return;
    }
    final bytes = await PluginIconCache.instance.load(url);
    if (!mounted) return;
    // 异步竞态保护：等待期间 URL 又变了，则丢弃这次结果
    if (_currentUrl != url) return;
    if (bytes != null && bytes.isNotEmpty) {
      setState(() => _bytes = bytes);
    } else if (_bytes != null) {
      // 新 URL 加载失败：清掉旧图，回退到默认图标而不是留旧图
      setState(() => _bytes = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty) return widget.fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => widget.fallback,
      ),
    );
  }
}

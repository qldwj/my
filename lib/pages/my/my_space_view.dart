import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';

enum MyDestination {
  theme,
  player,
  danmaku,
  rules,
  history,
  downloads,
  sync,
  storage,
  about,
}

const _tileRadius = BorderRadius.all(Radius.circular(28));

class MySpaceView extends StatelessWidget {
  const MySpaceView({
    super.key,
    required this.onOpen,
    required this.onLogin,
    required this.onFriends,
    this.socialProfile,
    this.friendRequestCount = 0,
    this.chatUnreadCount = 0,
    this.bangumiAvatarUrl = '',
    this.bangumiName = '',
    this.weeklyGoal = 0,
    this.thisWeekEpisodes = 0,
    this.onWeeklyGoalChanged,
  });

  final ValueChanged<MyDestination> onOpen;
  final VoidCallback onLogin;
  final VoidCallback onFriends;
  final SocialProfile? socialProfile;
  final int friendRequestCount;
  final int chatUnreadCount;
  final String bangumiAvatarUrl;
  final String bangumiName;
  final int weeklyGoal;
  final int thisWeekEpisodes;
  final ValueChanged<int>? onWeeklyGoalChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final inset = constraints.maxWidth < 600 ? 16.0 : 32.0;
      final width = (constraints.maxWidth - inset * 2).clamp(0.0, 1120.0);
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final wide = width >= 840 && !largeText;
      final columnWidth = wide ? (width - 12) / 2 : width;
      final stackTools = columnWidth < 300 || largeText;
      return SingleChildScrollView(
        key: const PageStorageKey('my-space'),
        padding: EdgeInsets.fromLTRB(inset, 12, inset, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 个人中心 + 账号面板 ──
                _AdaptivePair(
                  stack: !wide,
                  gap: 20,
                  first: _SpaceHeading(
                    socialProfile: socialProfile,
                    bangumiAvatarUrl: bangumiAvatarUrl,
                    bangumiName: bangumiName,
                  ),
                  second: _AccountPanel(
                    socialProfile: socialProfile,
                    friendRequestCount: friendRequestCount,
                    chatUnreadCount: chatUnreadCount,
                    onLogin: onLogin,
                    onFriends: onFriends,
                  ),
                ),
                const SizedBox(height: 28),
                // ── 本周目标 ──
                _WeeklyGoalCard(
                  weeklyGoal: weeklyGoal,
                  thisWeekEpisodes: thisWeekEpisodes,
                  onGoalChanged: onWeeklyGoalChanged,
                ),
                const SizedBox(height: 12),
                // ── 规则设置 + 历史记录/离线下载 ──
                _AdaptivePair(
                  stack: !wide,
                  gap: 12,
                  first: _RulesTile(onTap: () => onOpen(MyDestination.rules)),
                  second: _AdaptivePair(
                    stack: stackTools,
                    gap: 12,
                    first: _ToolTile(
                      icon: Icons.history_rounded,
                      title: '历史记录',
                      caption: '查看观看记录',
                      color: colors.secondaryContainer,
                      foreground: colors.onSecondaryContainer,
                      onTap: () => onOpen(MyDestination.history),
                    ),
                    second: _ToolTile(
                      icon: Icons.download_rounded,
                      title: '离线下载',
                      caption: '管理离线内容',
                      color: colors.tertiaryContainer,
                      foreground: colors.onTertiaryContainer,
                      onTap: () => onOpen(MyDestination.downloads),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── 偏好设置 + 同步备份/存储管理 ──
                _AdaptivePair(
                  stack: !wide,
                  gap: 12,
                  first: _PreferencesPanel(
                    onOpen: onOpen,
                    stack: columnWidth < 280 || largeText,
                  ),
                  second: _AdaptivePair(
                    stack: stackTools,
                    gap: 12,
                    first: _ToolTile(
                      icon: Icons.cloud_sync_rounded,
                      title: '同步备份',
                      caption: '跨设备同步数据',
                      color: colors.surfaceContainer,
                      foreground: colors.onSurface,
                      onTap: () => onOpen(MyDestination.sync),
                    ),
                    second: _ToolTile(
                      icon: Icons.cleaning_services_rounded,
                      title: '存储管理',
                      caption: '缓存与日志',
                      color: colors.surfaceContainer,
                      foreground: colors.onSurface,
                      onTap: () => onOpen(MyDestination.storage),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // ── 关于 ──
                Align(
                  alignment: Alignment.center,
                  child: _ExpressiveAction(
                    color: colors.surfaceContainerLow,
                    foreground: colors.onSurfaceVariant,
                    onTap: () => onOpen(MyDestination.about),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 20),
                          SizedBox(width: 8),
                          Flexible(child: Text('关于 Kazumi')),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ── 本周目标卡片 ──
class _WeeklyGoalCard extends StatelessWidget {
  const _WeeklyGoalCard({
    required this.weeklyGoal,
    required this.thisWeekEpisodes,
    this.onGoalChanged,
  });

  final int weeklyGoal;
  final int thisWeekEpisodes;
  final ValueChanged<int>? onGoalChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_rounded,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('本周目标',
                    style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface)),
              ],
            ),
            const SizedBox(height: 12),
            if (weeklyGoal <= 0)
              Column(
                children: [
                  Text(
                    '本周还没设定目标，本周已看 $thisWeekEpisodes 集',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => onGoalChanged?.call(5),
                    child: const Text('设定目标（5 集 / 周）'),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '本周已看 $thisWeekEpisodes / $weeklyGoal 集',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: weeklyGoal > 1
                            ? () => onGoalChanged?.call(weeklyGoal - 1)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onGoalChanged?.call(weeklyGoal + 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value:
                          (thisWeekEpisodes / weeklyGoal).clamp(0.0, 1.0),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    thisWeekEpisodes >= weeklyGoal
                        ? '🎉 本周目标已完成！'
                        : '还差 ${weeklyGoal - thisWeekEpisodes} 集达成目标',
                    style: TextStyle(
                      fontSize: 12,
                      color: thisWeekEpisodes >= weeklyGoal
                          ? Colors.green
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ── 账号面板（登录 + 好友）──
class _AccountPanel extends StatelessWidget {
  const _AccountPanel({
    required this.socialProfile,
    required this.friendRequestCount,
    required this.chatUnreadCount,
    required this.onLogin,
    required this.onFriends,
  });

  final SocialProfile? socialProfile;
  final int friendRequestCount;
  final int chatUnreadCount;
  final VoidCallback onLogin;
  final VoidCallback onFriends;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('账号',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _AccountAction(
                    icon: AuthService.isLoggedIn
                        ? Icons.check_circle_rounded
                        : Icons.login_rounded,
                    title: AuthService.isLoggedIn ? '已登录' : '登录',
                    subtitle: AuthService.isLoggedIn
                        ? (socialProfile?.nickname ?? '樱花动漫')
                        : '点击登录',
                    color: AuthService.isLoggedIn
                        ? Colors.green
                        : colors.primary,
                    badge: 0,
                    onTap: onLogin,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.swap_horiz_rounded,
                      color: colors.outlineVariant, size: 20),
                ),
                Expanded(
                  child: _AccountAction(
                    icon: Icons.people_rounded,
                    title: '好友',
                    subtitle: friendRequestCount > 0
                        ? '$friendRequestCount 个申请'
                        : '管理好友',
                    color: colors.tertiary,
                    badge: friendRequestCount,
                    onTap: onFriends,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 24),
              ),
              if (badge > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(title,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ── 标题区 ──
class _SpaceHeading extends StatelessWidget {
  const _SpaceHeading({
    required this.socialProfile,
    required this.bangumiAvatarUrl,
    required this.bangumiName,
  });

  final SocialProfile? socialProfile;
  final String bangumiAvatarUrl;
  final String bangumiName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '个人中心',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                      height: 1.2,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                AuthService.isLoggedIn
                    ? '欢迎回来，${socialProfile?.nickname ?? '用户'}'
                    : '登录以同步数据',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _ShapeIcon(
          shape: _SpaceShape.sun,
          icon: AuthService.isLoggedIn
              ? Icons.sentiment_satisfied_alt_rounded
              : Icons.person_outline_rounded,
          size: 64,
          color: colors.tertiaryContainer,
          foreground: colors.onTertiaryContainer,
        ),
      ],
    );
  }
}

// ── 规则设置大卡片 ──
class _RulesTile extends StatelessWidget {
  const _RulesTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return _ExpressiveAction(
      color: colors.primary,
      foreground: colors.onPrimary,
      radius: const BorderRadius.only(
        topLeft: Radius.circular(28),
        topRight: Radius.circular(64),
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('规则设置',
                      style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onPrimary)),
                  const SizedBox(height: 6),
                  Text('管理番剧来源',
                      style:
                          text.bodyMedium?.copyWith(color: colors.onPrimary)),
                  const SizedBox(height: 20),
                  _ArrowCue(
                      color: colors.onPrimary, foreground: colors.primary),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _ShapeIcon(
              shape: _SpaceShape.clover,
              icon: Icons.extension_rounded,
              size: 80,
              color: colors.primaryContainer,
              foreground: colors.onPrimaryContainer,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 工具磁贴 ──
class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.color,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _ExpressiveAction(
      color: color,
      foreground: foreground,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 30),
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
            const SizedBox(height: 26),
            Text(title,
                style: text.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: foreground)),
            const SizedBox(height: 6),
            Text(caption,
                style:
                    text.bodySmall?.copyWith(color: foreground, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

// ── 偏好设置面板 ──
class _PreferencesPanel extends StatelessWidget {
  const _PreferencesPanel({required this.onOpen, required this.stack});

  final ValueChanged<MyDestination> onOpen;
  final bool stack;

  static const _entries = [
    ('外观', Icons.palette_rounded, MyDestination.theme),
    ('播放', Icons.play_circle_rounded, MyDestination.player),
    ('弹幕', Icons.subtitles_rounded, MyDestination.danmaku),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final buttons = Flex(
      direction: stack ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _entries.length; i++) ...[
          if (i > 0) const SizedBox(width: 4, height: 4),
          if (stack) _button(i) else Expanded(child: _button(i)),
        ],
      ],
    );
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: _tileRadius,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('偏好设置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: colors.onSurface)),
            ),
            const SizedBox(height: 16),
            if (stack) buttons else IntrinsicHeight(child: buttons),
          ],
        ),
      ),
    );
  }

  Widget _button(int index) {
    final (label, icon, destination) = _entries[index];
    return _PreferenceAction(
      icon: icon,
      label: label,
      stack: stack,
      first: index == 0,
      last: index == _entries.length - 1,
      onTap: () => onOpen(destination),
    );
  }
}

class _PreferenceAction extends StatelessWidget {
  const _PreferenceAction({
    required this.icon,
    required this.label,
    required this.stack,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool stack;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = stack
        ? BorderRadius.vertical(
            top: Radius.circular(first ? 24 : 8),
            bottom: Radius.circular(last ? 24 : 8))
        : BorderRadius.horizontal(
            left: Radius.circular(first ? 24 : 8),
            right: Radius.circular(last ? 24 : 8));
    return _ExpressiveAction(
      color: colors.secondaryContainer,
      foreground: colors.onSecondaryContainer,
      radius: radius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 10),
            Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSecondaryContainer)),
          ],
        ),
      ),
    );
  }
}

// ── 全部设置按钮（AppBar 右上角）──
class MySettingsButton extends StatelessWidget {
  const MySettingsButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: '全部设置',
      child: _ExpressiveAction(
        color: colors.surfaceContainerHigh,
        foreground: colors.onSurface,
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 20),
              SizedBox(width: 8),
              Text('设置'),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 箭头指示 ──
class _ArrowCue extends StatelessWidget {
  const _ArrowCue({required this.color, required this.foreground});

  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: 52,
          height: 32,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(20)),
          child: Icon(Icons.arrow_forward_rounded, color: foreground, size: 20),
        ),
      );
}

// ── 装饰形状图标 ──
enum _SpaceShape { sun, clover }

class _ShapeIcon extends StatelessWidget {
  const _ShapeIcon({
    required this.shape,
    required this.icon,
    required this.size,
    required this.color,
    required this.foreground,
  });

  final _SpaceShape shape;
  final IconData icon;
  final double size;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: ClipPath(
          clipper: _SpaceShapeClipper(shape),
          child: ColoredBox(
            color: color,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, color: foreground, size: size * .44),
            ),
          ),
        ),
      );
}

class _SpaceShapeClipper extends CustomClipper<Path> {
  const _SpaceShapeClipper(this.shape);

  final _SpaceShape shape;

  @override
  Path getClip(Size size) {
    switch (shape) {
      case _SpaceShape.sun:
        return _sunPath(size);
      case _SpaceShape.clover:
        return _cloverPath(size);
    }
  }

  Path _sunPath(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = size.width / 2;
    final innerR = outerR * 0.7;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = (i * math.pi * 2 / 8) - math.pi / 2;
      final nextAngle = ((i + 0.5) * math.pi * 2 / 8) - math.pi / 2;
      final ox = cx + outerR * math.cos(angle);
      final oy = cy + outerR * math.sin(angle);
      final ix = cx + innerR * math.cos(nextAngle);
      final iy = cy + innerR * math.sin(nextAngle);
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    return path;
  }

  Path _cloverPath(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.22;
    final d = size.width * 0.18;
    final path = Path();
    final centers = [
      Offset(cx, cy - d),
      Offset(cx + d, cy),
      Offset(cx, cy + d),
      Offset(cx - d, cy),
    ];
    for (final c in centers) {
      path.addOval(Rect.fromCircle(center: c, radius: r));
    }
    path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.6));
    return path;
  }
}

// ── 可交互卡片基类（带动画）──
class _ExpressiveAction extends StatefulWidget {
  const _ExpressiveAction({
    required this.color,
    required this.foreground,
    required this.onTap,
    required this.child,
    this.radius = _tileRadius,
  });

  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  final Widget child;
  final BorderRadius radius;

  @override
  State<_ExpressiveAction> createState() => _ExpressiveActionState();
}

class _ExpressiveActionState extends State<_ExpressiveAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : Duration(milliseconds: _pressed ? 150 : 300);
    return Semantics(
      button: true,
      child: AnimatedScale(
        scale: _pressed && !reducedMotion ? .97 : 1,
        duration: duration,
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: _pressed ? BorderRadius.circular(16) : widget.radius,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return widget.foreground.withValues(alpha: .10);
                }
                if (states.contains(WidgetState.focused)) {
                  return widget.foreground.withValues(alpha: .12);
                }
                if (states.contains(WidgetState.hovered)) {
                  return widget.foreground.withValues(alpha: .08);
                }
                return null;
              }),
              child: IconTheme.merge(
                data: IconThemeData(color: widget.foreground),
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: widget.foreground,
                      ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 自适应双列布局 ──
class _AdaptivePair extends StatelessWidget {
  const _AdaptivePair({
    required this.first,
    required this.second,
    required this.stack,
    required this.gap,
  });

  final Widget first;
  final Widget second;
  final bool stack;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, SizedBox(height: gap), second],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          SizedBox(width: gap),
          Expanded(child: second),
        ],
      ),
    );
  }
}

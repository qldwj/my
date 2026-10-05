import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/settings/settings_detail_scaffold.dart';
import 'package:yhdm/bean/widget/settings_section_card.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/pages/settings/player_settings.dart';
import 'package:yhdm/utils/constants.dart';

/// 设置主页（总设置）
///
/// - 不含两个登录（在「我的」页）
/// - 不含历史记录 / 离线下载（在「我的」页）
/// - 仅包含全部设置项：下载与规则 / 播放器 / 数据与统计 / 应用与外观 / 其他
///
/// 布局参考官方 2.3.2「设置页面支持宽屏分栏布局」的思路
/// （LayoutBuilder 判宽 + RouterOutlet 承载右栏），但沿用本项目自己的
/// 分组 / 条目结构：
/// - 窄屏（宽度 <= 600）：整页显示设置列表，点条目整页打开（与以前一致）
/// - 宽屏（宽度 > 600）：左侧分组菜单常驻，右栏显示具体设置页
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.location});

  /// 当前路由路径（来自 `RouteState.uri.path`）
  final String location;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// 统一去掉结尾斜杠，便于比较（路由里 '/settings/plugin/' 与 '/settings/plugin' 等价）
String _normalizeSettingsPath(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

class _SettingsPageState extends State<SettingsPage> {
  final _outletKey = GlobalKey<RouterOutletState>();
  late String _location = _normalizeSettingsPath(widget.location);

  bool get _isRoot => _location.isEmpty || _location == '/settings';

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      setState(() => _location = _normalizeSettingsPath(widget.location));
    }
  }

  /// 宽屏点左栏：替换右栏内容（不留返回栈），与官方 _replaceCategory 同理
  void _selectEntry(SettingsEntrySpec entry) {
    final path = entry.path;
    if (path != null) {
      // 路由里带不带结尾斜杠都能被 outlet 解析，这里原样传入
      _outletKey.currentState?.navigate(path);
      setState(() => _location = _normalizeSettingsPath(path));
      return;
    }
    final page = entry.page;
    if (page != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }
  }

  /// 返回：先退右栏，退不动才退出设置
  void _goBack() {
    if (_outletKey.currentState?.maybePop() ?? false) {
      return;
    }
    _exitSettings();
  }

  void _exitSettings() {
    if (!context.maybePop()) {
      context.navigate('/tab/my');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // NavigatorPopHandler 是嵌套导航的官方做法：只有右栏还能回退时才接管返回键，
    // 右栏已到底则正常退出设置（不会像 PopScope(canPop:false) 那样递归）
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (_) => _goBack(),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide =
            constraints.maxWidth > LayoutBreakpoint.compact['width']!;
        return Scaffold(
          body: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 宽屏常驻左栏；窄屏不占位，保持原有整页体验
                if (wide) ...[
                  SizedBox(
                    width: 260,
                    child: _SettingsRail(
                      groups: _buildGroups(l10n),
                      selectedPath: _location,
                      onSelect: _selectEntry,
                      onBack: _goBack,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                ],
                Expanded(
                  child: SettingsPaneScope(
                    // 嵌在右栏时，用 SettingsDetailScaffold 的页面会切成「面板」样式
                    embedded: wide,
                    showBackButton: wide && !_isRoot,
                    onBack: _goBack,
                    child: RouterOutlet(key: _outletKey),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// 设置列表（窄屏时作为主体；宽屏时作为右栏默认页）
class SettingsIndexPage extends StatelessWidget {
  const SettingsIndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 宽屏分栏时，右栏直接展示常用的「播放设置」，避免出现空白栏
    if (SettingsPaneScope.of(context)?.embedded ?? false) {
      return const PlayerSettingsPage();
    }
    return Scaffold(
      appBar: SysAppBar(title: Text(l10n.settings)),
      body: _SettingsList(
        groups: _buildGroups(l10n),
        onSelect: (entry) => _openEntry(context, entry),
      ),
    );
  }
}

/// 打开一个设置项（窄屏整页打开，行为与改动前一致）
void _openEntry(BuildContext context, SettingsEntrySpec entry) {
  final path = entry.path;
  if (path != null) {
    context.pushNamed(path);
    return;
  }
  final page = entry.page;
  if (page != null) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

/// ── 设置条目清单（列表与左栏共用，只维护一份）──
class SettingsEntrySpec {
  const SettingsEntrySpec({
    required this.icon,
    required this.title,
    this.description,
    this.path,
    this.page,
  }) : assert(path != null || page != null, '设置项需要 path 或 page');

  final IconData icon;
  final String title;
  final String? description;

  /// 模块路由（可被右栏承载）
  final String? path;

  /// 未注册为路由的页面（用 Navigator 整页打开，如镜像代理 / 意见反馈）
  final Widget? page;
}

class _SettingsGroup {
  const _SettingsGroup({required this.title, required this.entries});

  final String title;
  final List<SettingsEntrySpec> entries;
}

List<_SettingsGroup> _buildGroups(AppLocalizations l10n) {
  return [
    _SettingsGroup(
      title: l10n.settingsGroupDownloadRules,
      entries: [
        SettingsEntrySpec(
          icon: Icons.settings_rounded,
          title: l10n.downloadSettings,
          description: l10n.downloadSettingsDesc,
          path: '/settings/download-settings',
        ),
        SettingsEntrySpec(
          icon: Icons.extension_rounded,
          title: l10n.ruleManager,
          description: l10n.ruleManagerDesc,
          path: '/settings/plugin/',
        ),
      ],
    ),
    _SettingsGroup(
      title: l10n.playerSettingsGroup,
      entries: [
        SettingsEntrySpec(
          icon: Icons.display_settings_rounded,
          title: l10n.playbackSettings,
          description: l10n.playbackSettingsDesc,
          path: '/settings/player',
        ),
        SettingsEntrySpec(
          icon: Icons.subtitles_rounded,
          title: l10n.danmakuSettings,
          description: l10n.danmakuSettingsDesc,
          path: '/settings/danmaku/',
        ),
        SettingsEntrySpec(
          icon: Icons.notifications_active_rounded,
          title: l10n.followNotify,
          description: l10n.followNotifyDesc,
          path: '/settings/notification',
        ),
        SettingsEntrySpec(
          icon: Icons.vpn_key_rounded,
          title: l10n.mirrorProxy,
          description: l10n.mirrorProxyDesc,
          path: '/settings/mirror-proxy',
        ),
      ],
    ),
    _SettingsGroup(
      title: l10n.dataStatsGroup,
      entries: [
        SettingsEntrySpec(
          icon: Icons.cloud_rounded,
          title: l10n.syncSettings,
          description: l10n.syncSettingsDesc,
          path: '/settings/sync',
        ),
      ],
    ),
    _SettingsGroup(
      title: l10n.appAppearanceGroup,
      entries: [
        SettingsEntrySpec(
          icon: Icons.palette_rounded,
          title: l10n.appearanceSettings,
          description: l10n.appearanceSettingsDesc,
          path: '/settings/theme',
        ),
        SettingsEntrySpec(
          icon: Icons.color_lens_rounded,
          title: l10n.themeSkinTitle,
          description: l10n.themeSkinDesc,
          path: '/settings/theme/skin',
        ),
        SettingsEntrySpec(
          icon: Icons.pages_rounded,
          title: l10n.interfaceSettings,
          description: l10n.interfaceSettingsDesc,
          path: '/settings/interface',
        ),
        SettingsEntrySpec(
          icon: Icons.language_rounded,
          title: l10n.languageTitle,
          description: l10n.languageFollowSystem,
          path: '/settings/language',
        ),
      ],
    ),
    _SettingsGroup(
      title: l10n.othersGroup,
      entries: [
        SettingsEntrySpec(
          icon: Icons.feedback_rounded,
          title: l10n.feedback,
          description: l10n.feedbackDesc,
          path: '/settings/feedback',
        ),
        SettingsEntrySpec(
          icon: Icons.info_outline_rounded,
          title: l10n.about,
          path: '/settings/about/',
        ),
      ],
    ),
  ];
}

/// 窄屏设置列表（与原设置页视觉一致）
class _SettingsList extends StatelessWidget {
  const _SettingsList({required this.onSelect, required this.groups});

  final ValueChanged<SettingsEntrySpec> onSelect;
  final List<_SettingsGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final group in groups)
              SettingsSectionCard(
                title: group.title,
                children: [
                  for (final entry in group.entries)
                    SettingsEntryTile(
                      icon: entry.icon,
                      title: entry.title,
                      description: entry.description,
                      onTap: () => onSelect(entry),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 宽屏左栏：分组 + 条目
class _SettingsRail extends StatelessWidget {
  const _SettingsRail({
    required this.groups,
    required this.selectedPath,
    required this.onSelect,
    required this.onBack,
  });

  final List<_SettingsGroup> groups;
  final String selectedPath;
  final ValueChanged<SettingsEntrySpec> onSelect;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.backTooltip,
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Text(
                l10n.settings,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              group.title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final entry in group.entries)
            _SettingsRailTile(
              icon: entry.icon,
              title: entry.title,
              selected: entry.path != null &&
                  _normalizeSettingsPath(entry.path!) == selectedPath,
              onTap: () => onSelect(entry),
            ),
        ],
      ],
    );
  }
}

class _SettingsRailTile extends StatelessWidget {
  const _SettingsRailTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? colors.onSecondaryContainer
                          : colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

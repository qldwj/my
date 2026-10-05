import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/router.dart';

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key, required this.location});

  final String location;

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class _ScaffoldMenu extends State<ScaffoldMenu> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
  DateTime? _lastExitPromptAt;
  late int _selectedIndex = menu.indexForPath(widget.location);

  /// The shell sits at the bottom of the root stack and stays mounted while
  /// other pages cover it, so it publishes that state for its subtree.
  bool _isCovered = false;

  @override
  void didUpdateWidget(covariant ScaffoldMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _selectedIndex = menu.indexForPath(widget.location);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool value) {
    if (!mounted || _isCovered == value) {
      return;
    }
    setState(() => _isCovered = value);
  }

  void _selectDestination(int index) {
    _lastExitPromptAt = null;
    if (index == _selectedIndex) {
      return;
    }
    final outlet = _outletKey.currentState;
    if (outlet == null) return;
    outlet.navigate('/tab${menu.getPath(index)}/');
    setState(() => _selectedIndex = index);
  }

  void _handleSystemBack(BuildContext context) {
    if (_outletKey.currentState?.maybePop() ?? false) {
      _lastExitPromptAt = null;
      return;
    }

    if (_selectedIndex != 0) {
      _selectDestination(0);
      return;
    }

    final now = DateTime.now();
    final lastPromptAt = _lastExitPromptAt;
    if (lastPromptAt == null ||
        now.difference(lastPromptAt) > const Duration(seconds: 2)) {
      _lastExitPromptAt = now;
      KazumiDialog.showToast(message: AppLocalizations.of(context)!.setGPressBackAgainToExit, context: context);
      return;
    }

    _lastExitPromptAt = null;
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return RouteVisibility(
      isCovered: _isCovered,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _handleSystemBack(context);
          }
        },
        child: OrientationBuilder(
          builder: (context, orientation) {
            return orientation == Orientation.portrait
                ? _bottomMenu(context, _selectedIndex)
                : _sideMenu(context, _selectedIndex);
          },
        ),
      ),
    );
  }

  Widget _outlet(BuildContext context, {BorderRadius? borderRadius}) {
    Widget child = NotificationListener<NavigationNotification>(
      // A non-poppable outlet must not override the shell's PopScope state.
      onNotification: (notification) => !notification.canHandlePop,
      child: RouterOutlet(key: _outletKey),
    );
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius, child: child);
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }

  Widget _bottomMenu(BuildContext context, int selectedIndex) {
    return Scaffold(
      body: _outlet(context),
      bottomNavigationBar: _AnimatedNavBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: _selectDestination,
      ),
    );
  }

  Widget _sideMenu(BuildContext context, int selectedIndex) {
    final l10n = AppLocalizations.of(context)!;
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(16),
      bottomLeft: Radius.circular(16),
    );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Row(
        children: [
          EmbeddedNativeControlArea(
            child: NavigationRail(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              groupAlignment: 1,
              leading: FloatingActionButton(
                elevation: 0,
                heroTag: null,
                onPressed: () => context.pushNamed('/search/'),
                child: const Icon(Icons.search),
              ),
              labelType: NavigationRailLabelType.selected,
              destinations: <NavigationRailDestination>[
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.home),
                  icon: Icon(Icons.home_outlined),
                  label: Text(l10n.setGTabRecommend),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.timeline),
                  icon: Icon(Icons.timeline_outlined),
                  label: Text(l10n.setGTabTimeline),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.favorite),
                  icon: Icon(Icons.favorite_border),
                  label: Text(l10n.setGTabFollow),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.settings),
                  icon: Icon(Icons.settings_outlined),
                  label: Text(l10n.setGTabMine),
                ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: _selectDestination,
            ),
          ),
          Expanded(child: _outlet(context, borderRadius: borderRadius)),
        ],
      ),
    );
  }
}

/// 底部导航：选中高亮条在 tab 间水平平移 + 选中图标缩放上浮
class _AnimatedNavBar extends StatelessWidget {
  const _AnimatedNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final items = <({IconData icon, IconData selIcon, String label})>[
      (icon: Icons.home_outlined, selIcon: Icons.home, label: l10n.setGTabRecommend),
      (icon: Icons.timeline_outlined, selIcon: Icons.timeline, label: l10n.setGTabTimeline),
      (icon: Icons.favorite_outlined, selIcon: Icons.favorite, label: l10n.setGTabFollow),
      (icon: Icons.settings_outlined, selIcon: Icons.settings, label: l10n.setGTabMine),
    ];
    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final itemW = w / items.length;
              final pillW = itemW - 36;
              return Stack(
                children: [
                  // 高亮指示条：选中项之间水平平移（不重载页面）
                  AnimatedPositioned(
                    left: selectedIndex * itemW + (itemW - pillW) / 2,
                    top: 10,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: Container(
                      width: pillW,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(items.length, (i) {
                      final it = items[i];
                      final sel = i == selectedIndex;
                      return Expanded(
                        child: InkWell(
                          onTap: () => onDestinationSelected(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedScale(
                                scale: sel ? 1.12 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                                child: Icon(
                                  sel ? it.selIcon : it.icon,
                                  size: 23,
                                  color: sel ? cs.primary : cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                it.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                                  color: sel ? cs.primary : cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

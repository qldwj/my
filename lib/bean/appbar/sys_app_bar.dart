import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/settings/settings_detail_scaffold.dart';
import 'package:yhdm/bean/widget/embedded_native_control_area.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yhdm/utils/device.dart';

class SysAppBar extends StatelessWidget implements PreferredSizeWidget {
  final double? toolbarHeight;

  final Widget? title;

  final Color? backgroundColor;

  final double? elevation;

  final ShapeBorder? shape;

  final List<Widget>? actions;

  final Widget? leading;

  final double? leadingWidth;

  final PreferredSizeWidget? bottom;

  final bool needTopOffset;

  const SysAppBar(
      {super.key,
      this.toolbarHeight,
      this.title,
      this.backgroundColor,
      this.elevation,
      this.shape,
      this.actions,
      this.leading,
      this.leadingWidth,
      this.bottom,
      this.needTopOffset = true});

  bool showWindowButton() {
    return GStorage.getSetting(SettingsKeys.showWindowButton);
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> acs = [];
    if (actions != null) {
      acs.addAll(actions!);
    }
    final inSettingsPane = SettingsPaneScope.of(context)?.embedded ?? false;
    if (isDesktop() && !inSettingsPane) {
      // 🔴 修复：宽屏设置右栏面板（embedded）里不再补画窗口关闭按钮，
      // 否则每个用 SysAppBar 的设置子页面都会多出一个 X（与面板内的返回按钮重复）。
      if (!showWindowButton()) {
        acs.add(CloseButton(onPressed: () => windowManager.close()));
      }
      acs.add(const SizedBox(width: 8));
    }
    return GestureDetector(
      onPanStart: (_) => (isDesktop()) ? windowManager.startDragging() : null,
      child: AppBar(
        toolbarHeight: preferredSize.height,
        scrolledUnderElevation: 0.0,
        title: title != null
            ? EmbeddedNativeControlArea(
                requireOffset: needTopOffset,
                child: title!,
              )
            : null,
        centerTitle: Platform.isIOS ? true : false,
        actions: acs.map((e) {
          return EmbeddedNativeControlArea(
            requireOffset: needTopOffset,
            child: e,
          );
        }).toList(),
        leading: leading != null
            ? EmbeddedNativeControlArea(
                requireOffset: needTopOffset,
                child: leading!,
              )
            : (ModalRoute.of(context)?.impliesAppBarDismissal ?? false)
                ? EmbeddedNativeControlArea(
                    requireOffset: needTopOffset,
                    child: IconButton(
                      onPressed: () {
                        context.maybePop();
                      },
                      icon: Icon(Icons.arrow_back),
                    ),
                  )
                : null,
        leadingWidth: leadingWidth,
        backgroundColor: backgroundColor,
        elevation: elevation,
        shape: shape,
        bottom: bottom,
        automaticallyImplyLeading: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Theme.of(context).brightness == Brightness.light
                  ? Brightness.dark
                  : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      ),
    );
  }

  @override
  Size get preferredSize {
    double baseHeight = toolbarHeight ?? kToolbarHeight;
    // macOS needs to add 22(macOS title bar height)
    // to default toolbar height to build appbar like normal
    if (Platform.isMacOS && needTopOffset && showWindowButton()) {
      baseHeight += 22;
    }
    // Include bottom widget height (e.g. TabBar)
    if (bottom != null) {
      final bottomSize = bottom!.preferredSize;
      baseHeight += bottomSize.height;
    }
    return Size.fromHeight(baseHeight);
  }
}

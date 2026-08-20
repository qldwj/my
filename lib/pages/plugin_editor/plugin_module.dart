import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/plugin_editor/plugin_editor_page.dart';
import 'package:kazumi/pages/plugin_editor/plugin_shop_page.dart';
import 'package:kazumi/pages/plugin_editor/plugin_test_page.dart';
import 'package:kazumi/pages/plugin_editor/plugin_view_page.dart';
import 'package:kazumi/pages/plugin_login/plugin_login_page.dart';
import 'package:kazumi/pages/route_error_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

final pluginModule = createModule(
  path: '/plugin',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => PluginViewPage(
          controller: inject<PluginsController>(),
        ),
      )
      ..route(
        '/shop',
        child: (context, state) => PluginShopPage(
          controller: inject<PluginsController>(),
        ),
      )
      ..route(
        '/test',
        child: (context, state) {
          final plugin = state.arguments;
          if (plugin is! Plugin) {
            return const RouteErrorPage(message: '规则测试参数无效，请返回后重试。');
          }
          return PluginTestPage(plugin: plugin);
        },
      )
      ..route(
        '/editor',
        child: (context, state) {
          final plugin = state.arguments;
          if (plugin is! Plugin) {
            return const RouteErrorPage(message: '规则编辑参数无效，请返回后重试。');
          }
          return PluginEditorPage(
            plugin: plugin,
            controller: inject<PluginsController>(),
          );
        },
      )
      ..route(
        '/login',
        child: (context, state) {
          final plugin = state.arguments;
          if (plugin is! Plugin || plugin.loginUrl.isEmpty) {
            return const RouteErrorPage(message: '该规则未配置登录地址。');
          }
          return PluginLoginPage(
            pluginName: plugin.name,
            loginUrl: plugin.loginUrl,
          );
        },
      );
  },
);

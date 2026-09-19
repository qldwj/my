import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/about/about_module.dart';
import 'package:kazumi/pages/bangumi/bangumi_module.dart';
import 'package:kazumi/pages/download/download_page_module.dart';
import 'package:kazumi/pages/history/history_module.dart';
import 'package:kazumi/pages/plugin_editor/plugin_module.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/settings/decoder_settings.dart';
import 'package:kazumi/pages/settings/desktop_settings_page.dart';
import 'package:kazumi/pages/settings/displaymode_settings.dart';
import 'package:kazumi/pages/settings/download_settings.dart';
import 'package:kazumi/pages/settings/interface_settings.dart';
import 'package:kazumi/pages/settings/keyboard_settings.dart';
import 'package:kazumi/pages/settings/notification_settings_page.dart';
import 'package:kazumi/pages/settings/player_settings.dart';
import 'package:kazumi/pages/settings/proxy/proxy_module.dart';
import 'package:kazumi/pages/settings/renderer_settings.dart';
import 'package:kazumi/pages/settings/settings_page.dart';
import 'package:kazumi/pages/settings/super_resolution_settings.dart';
import 'package:kazumi/pages/settings/webview_embed_page.dart';
import 'package:kazumi/pages/settings/theme_settings_page.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_page.dart';
import 'package:kazumi/pages/settings/sync/bangumi_sync_page.dart';
import 'package:kazumi/pages/webdav_editor/webdav_module.dart';

final settingsModule = createModule(
  path: '/settings',
  register: (c) {
    c
      // ⭐ 设置外壳（参考官方 2.3.2「设置页面支持宽屏分栏布局」的写法）：
      // 所有设置子路由都挂到这里，宽屏时右栏用 RouterOutlet 承载，
      // 窄屏时整页显示，路径与之前完全一致（/settings/xxx）。
      ..route(
        '/',
        child: (context, state) => SettingsPage(location: state.uri.path),
        children: (sub) {
          sub
            // 设置列表（窄屏主体；宽屏时作为右栏默认页）
            ..route('/', child: (context, state) => const SettingsIndexPage())
            ..route('/theme',
                child: (context, state) => const ThemeSettingsPage())
            ..route('/webview',
                child: (context, state) => const WebviewEmbedPage())
            ..route('/theme/display',
                child: (context, state) => const SetDisplayMode())
            ..route('/keyboard',
                child: (context, state) => const KeyboardSettingsPage())
            ..route('/player',
                child: (context, state) => const PlayerSettingsPage())
            ..route('/player/decoder',
                child: (context, state) => const DecoderSettings())
            ..route('/player/renderer',
                child: (context, state) => const RendererSettings())
            ..route('/interface',
                child: (context, state) => const InterfaceSettingsPage())
            ..module(proxyModule)
            ..route('/player/super',
                child: (context, state) => const SuperResolutionSettings())
            ..module(webDavModule)
            ..module(aboutModule)
            ..module(pluginModule)
            ..module(historyModule)
            ..module(danmakuModule)
            ..module(downloadModule)
            ..route('/download-settings',
                child: (context, state) => const DownloadSettingsPage())
            ..route('/notification',
                child: (context, state) => const NotificationSettingsPage())
            ..route('/desktop',
                child: (context, state) => const DesktopSettingsPage())
            ..route('/sync',
                child: (context, state) => const SyncSettingsPage())
            ..route('/sync/bangumi',
                child: (context, state) => const BangumiSyncPage())
            ..module(bangumiModule);
        },
      );
  },
);

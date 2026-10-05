import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/pages/info/info_controller.dart';
import 'package:yhdm/pages/info/info_page.dart';
import 'package:yhdm/pages/route_error_page.dart';
import 'package:yhdm/plugins/plugins_controller.dart';

final infoModule = createModule(
  path: '/info',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s.add<InfoController>(InfoController.new),
      child: (context, state) {
        final bangumiItem = state.arguments;
        if (bangumiItem is! BangumiItem) {
          return const RouteErrorPage(message: '番组详情参数无效，请返回后重新打开。');
        }
        return InfoPage(
          inputBangumiItem: bangumiItem,
          infoController: context.read<InfoController>(),
          pluginsController: inject<PluginsController>(),
        );
      },
    );
  },
);

import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/stats/stats_page.dart';

final statsModule = createModule(
  path: '/stats',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => const StatsPage(),
    );
  },
);

import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/recommend/recommend_page.dart';

final recommendModule = createModule(
  path: '/recommend',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => const RecommendPage(),
    );
  },
);

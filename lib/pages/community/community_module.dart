import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/pages/community/community_page.dart';

final communityModule = createModule(
  path: '/community',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => const CommunityPage(),
    );
  },
);

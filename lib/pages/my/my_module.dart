import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/pages/my/my_page.dart';
import 'package:yhdm/pages/my/kazumi_login_page.dart';
import 'package:yhdm/pages/my/checkin_page.dart';

final myModule = createModule(
  path: '/my',
  register: (c) {
    c
      ..route(
        '/',
        transition: TransitionType.none,
        child: (context, state) => const MyPage(),
      )
      ..route(
        '/login',
        child: (context, state) => const KazumiLoginPage(),
      )
      ..route(
        '/checkin',
        child: (context, state) => const CheckinPage(),
      );
  },
);

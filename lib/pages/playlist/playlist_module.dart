import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/pages/playlist/playlist_page.dart';

final playlistModule = createModule(
  path: '/playlist',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => const PlaylistPage(),
    );
  },
);

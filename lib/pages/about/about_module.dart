import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/about/about_page.dart';
import 'package:kazumi/pages/about/credits_page.dart';
import 'package:kazumi/pages/logs/logs_page.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/l10n/app_localizations.dart';

final aboutModule = createModule(
  path: '/about',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => AboutPage(
          controller: inject<MyController>(),
        ),
      )
      ..route('/logs', child: (context, state) => const LogsPage())
      ..route('/credits', child: (context, state) => const CreditsPage())
      ..route(
        '/license',
        child: (context, state) => LicensePage(
          applicationName: 'YHDM',
          applicationVersion: ApiEndpoints.version,
          applicationLegalese:
              AppLocalizations.of(context)!.setCOpenSourceLicense,
        ),
      );
  },
);

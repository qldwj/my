import 'package:flutter/material.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/pages/onboarding/onboarding_step_layout.dart';
import 'package:kazumi/pages/plugin_editor/plugin_catalog_view.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

class PluginShopStep extends StatelessWidget {
  const PluginShopStep({
    super.key,
    required this.controller,
  });

  final PluginsController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepLayout(
      leading: const OnboardingStepIcon(icon: Icons.travel_explore_rounded),
      title: l10n.pluginTitle,
      subtitle: l10n.pluginSubtitle,
      child: PluginCatalogView(
        controller: controller,
        listPadding: EdgeInsets.zero,
        showRefreshButton: true,
        compactLastUpdate: true,
      ),
    );
  }
}

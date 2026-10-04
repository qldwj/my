import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/pages/plugin_editor/market_page.dart';
import 'package:kazumi/pages/plugin_editor/plugin_catalog_view.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

class PluginShopPage extends StatefulWidget {
  const PluginShopPage({
    super.key,
    required this.controller,
  });

  final PluginsController controller;

  @override
  State<PluginShopPage> createState() => _PluginShopPageState();
}

class _PluginShopPageState extends State<PluginShopPage> {
  final catalogKey = GlobalKey<PluginCatalogViewState>();
  bool sortByName = false;

  void _toggleSort() {
    setState(() {
      sortByName = !sortByName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SysAppBar(
        title: Text(l10n.setFRuleRepository),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MarketPage(controller: widget.controller),
              ),
            ),
            tooltip: l10n.setFRuleMarketUserUpload,
            icon: const Icon(Icons.storefront_outlined),
          ),
          IconButton(
              onPressed: _toggleSort,
              tooltip: sortByName ? l10n.setFSortByName : l10n.setFSortByUpdatedAt,
              icon: Icon(sortByName ? Icons.sort_by_alpha : Icons.access_time)),
          IconButton(
              onPressed: () => catalogKey.currentState?.refresh(),
              tooltip: l10n.setFRefreshRuleList,
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: PluginCatalogView(
        key: catalogKey,
        controller: widget.controller,
        sort:
            sortByName ? PluginCatalogSort.name : PluginCatalogSort.lastUpdate,
        errorMessage: l10n.setFRepoUnreachable,
      ),
    );
  }
}

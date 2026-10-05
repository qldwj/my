import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/settings/settings_detail_scaffold.dart';
import 'package:yhdm/bean/settings/settings_list.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/services/storage/image_cache_service.dart';

class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  final _cache = ImageCacheService();
  late Future<int> _cacheSize = _cache.sizeInBytes();
  bool _clearing = false;

  void _refreshSize() => setState(() => _cacheSize = _cache.sizeInBytes());

  void _message(String message) {
    KazumiDialog.showToast(context: context, message: message);
  }

  Future<void> _confirmClear() async {
    if (_clearing) return;
    final confirmed = await KazumiDialog.show<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          icon: const Icon(Icons.cleaning_services_rounded),
          title: Text(l10n.setAClearCacheAsk),
          content: Text(l10n.setAClearCacheDesc),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.setAClearCacheAction),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await _cache.clear();
      if (!mounted) return;
      _message(AppLocalizations.of(context)!.setACacheCleared);
      _refreshSize();
    } catch (_) {
      if (mounted) _message(AppLocalizations.of(context)!.setAClearCacheFail);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  String _cacheDescription(AsyncSnapshot<int> snapshot) {
    final l10n = AppLocalizations.of(context)!;
    if (_clearing) return l10n.setAClearing;
    if (snapshot.connectionState != ConnectionState.done) return l10n.setAStatting;
    if (snapshot.hasError) return l10n.setAStatFailed;
    return '${(snapshot.requireData / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsDetailScaffold(
        title: Text(l10n.setAStorageLogs),
        body: FutureBuilder<int>(
          future: _cacheSize,
          builder: (context, snapshot) => SettingsList(
            sections: [
              SettingsSection(
                title: Text(l10n.setACache),
                tiles: [
                  SettingsTile(
                    leading: Icons.image_outlined,
                    title: Text(l10n.setAClearImageCache),
                    description: Text(_cacheDescription(snapshot)),
                    enabled: snapshot.connectionState == ConnectionState.done &&
                        !_clearing,
                    onPressed: (_) => _confirmClear(),
                    trailing:
                        snapshot.connectionState == ConnectionState.done &&
                                snapshot.hasError &&
                                !_clearing
                            ? IconButton(
                                tooltip: l10n.setARestat,
                                onPressed: _refreshSize,
                                icon: const Icon(Icons.refresh_rounded),
                              )
                            : const Icon(Icons.cleaning_services_rounded),
                  ),
                ],
              ),
              SettingsSection(
                title: Text(l10n.setADiagnostics),
                tiles: [
                  SettingsTile(
                    leading: Icons.receipt_long_rounded,
                    title: Text(l10n.setAErrorLogs),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onPressed: (_) =>
                        context.pushNamed('/settings/storage/logs'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
}

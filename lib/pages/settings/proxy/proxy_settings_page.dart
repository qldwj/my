import 'package:flutter/material.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/settings/network_mirror_settings.dart';
import 'package:yhdm/bean/settings/settings_list.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/network/proxy_manager.dart';
import 'package:yhdm/l10n/app_localizations.dart';

class ProxySettingsPage extends StatefulWidget {
  const ProxySettingsPage({super.key});

  @override
  State<ProxySettingsPage> createState() => _ProxySettingsPageState();
}

class _ProxySettingsPageState extends State<ProxySettingsPage> {
  late bool proxyEnable;

  @override
  void initState() {
    super.initState();
    proxyEnable = GStorage.getSetting(SettingsKeys.proxyEnable);
  }

  void onBackPressed(BuildContext context) {
    if (KazumiDialog.observer.hasKazumiDialog) {
      KazumiDialog.dismiss();
      return;
    }
  }

  Future<void> updateProxyEnable(bool value) async {
    if (value) {
      final proxyConfigured = GStorage.getSetting(SettingsKeys.proxyConfigured);
      if (!proxyConfigured) {
        KazumiDialog.showToast(message: AppLocalizations.of(context)!.setCPleaseTestInProxyConfig);
        return;
      }
      await GStorage.putSetting(SettingsKeys.proxyEnable, true);
      ProxyManager.applyProxy();
    } else {
      await GStorage.putSetting(SettingsKeys.proxyEnable, false);
      ProxyManager.clearProxy();
    }
    setState(() {
      proxyEnable = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: SysAppBar(title: Text(l10n.setCNetworkSettings)),
        body: SettingsList(
          maxWidth: 800,
          sections: [
            const NetworkMirrorSettings(),
            SettingsSection(
              title: Text(l10n.setCProxy),
              tiles: [
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    await updateProxyEnable(value ?? !proxyEnable);
                  },
                  title: Text(l10n.setCEnableProxy),
                  description: Text(l10n.setCEnableProxyDesc),
                  initialValue: proxyEnable,
                ),
                SettingsTile(
                  onPressed: (_) async {
                    await context.pushNamed('/settings/proxy/editor');
                    setState(() {
                      proxyEnable =
                          GStorage.getSetting(SettingsKeys.proxyEnable);
                    });
                  },
                  title: Text(l10n.setCProxyConfig),
                  description: Text(l10n.setCProxyConfigDesc),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

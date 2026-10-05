import 'package:flutter/material.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/settings/settings_detail_scaffold.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/network/proxy_utils.dart';
import 'package:yhdm/services/network/proxy_manager.dart';
import 'package:yhdm/request/core/dio_factory.dart';
import 'package:yhdm/request/core/network_config.dart';
import 'package:yhdm/l10n/app_localizations.dart';

class ProxyEditorPage extends StatefulWidget {
  const ProxyEditorPage({super.key});

  @override
  State<ProxyEditorPage> createState() => _ProxyEditorPageState();
}

class _ProxyEditorPageState extends State<ProxyEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController urlController = TextEditingController();
  final TextEditingController testUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    urlController.text = GStorage.getSetting(SettingsKeys.proxyUrl);
    testUrlController.text = GStorage.getSetting(SettingsKeys.proxyTestUrl);
  }

  @override
  void dispose() {
    urlController.dispose();
    testUrlController.dispose();
    super.dispose();
  }

  Future<void> saveAndTest() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final url = urlController.text.trim();
    if (url.isEmpty) {
      KazumiDialog.showToast(message: l10n.setCEnterProxyAddress);
      return;
    }

    final testUrl = testUrlController.text.trim().isEmpty
        ? 'https://www.google.com'
        : testUrlController.text.trim();

    await GStorage.putSetting(SettingsKeys.proxyUrl, url);
    await GStorage.putSetting(SettingsKeys.proxyTestUrl, testUrl);
    await GStorage.putSetting(SettingsKeys.proxyConfigured, false);

    await GStorage.putSetting(SettingsKeys.proxyEnable, true);
    ProxyManager.applyProxy();

    try {
      final parsed = ProxyUtils.parseProxyUrl(url);
      if (parsed == null) {
        throw StateError('Invalid proxy URL');
      }
      final dio = DioFactory.createForConfig(
        NetworkConfig(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          proxyHost: parsed.$1,
          proxyPort: parsed.$2,
          allowBadCertificates: true,
          enableLog: false,
        ),
      );
      await dio
          .get(
            testUrl,
          )
          .timeout(const Duration(seconds: 15));
      await GStorage.putSetting(SettingsKeys.proxyConfigured, true);
      KazumiDialog.showToast(message: l10n.setCTestSuccess);
    } catch (e) {
      await GStorage.putSetting(SettingsKeys.proxyEnable, false);
      ProxyManager.clearProxy();
      KazumiDialog.showToast(message: l10n.setCProxyConnectionFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsDetailScaffold(
      title: Text(l10n.setCProxyConfig),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SizedBox(
            width: (MediaQuery.of(context).size.width > 800) ? 800 : null,
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: urlController,
                    decoration: InputDecoration(
                      labelText: l10n.setCProxyAddress,
                      hintText: 'http://127.0.0.1:7890',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.setCEnterProxyAddress;
                      }
                      if (!ProxyUtils.isValidProxyUrl(value)) {
                        return l10n.setCProxyFormatError;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: testUrlController,
                    decoration: InputDecoration(
                      labelText: l10n.setCTestAddress,
                      hintText: 'https://www.google.com',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: saveAndTest,
        icon: const Icon(Icons.save),
        label: Text(l10n.setCSaveAndTest),
      ),
    );
  }
}

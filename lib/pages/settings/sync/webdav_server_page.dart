import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/bean/widget/tonal_card.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_widgets.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/webdav.dart';

class WebDavServerPage extends StatefulWidget {
  const WebDavServerPage({super.key});

  @override
  State<WebDavServerPage> createState() => _WebDavServerPageState();
}

class _WebDavServerPageState extends State<WebDavServerPage> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _passwordVisible = false;
  bool _busy = false;
  bool _failed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _url.text = GStorage.getSetting(SettingsKeys.webDavURL);
    _username.text = GStorage.getSetting(SettingsKeys.webDavUsername);
    _password.text = GStorage.getSetting(SettingsKeys.webDavPassword);
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _failed = false;
      _message = l10n.setBTestingConnection;
    });
    try {
      await GStorage.putSetting(SettingsKeys.webDavURL, _url.text.trim());
      await GStorage.putSetting(
          SettingsKeys.webDavUsername, _username.text.trim());
      await GStorage.putSetting(SettingsKeys.webDavPassword, _password.text);
      await WebDav().init();
      _message = l10n.setBTestSuccess;
    } catch (e) {
      KazumiLogger().w('WebDAV configuration failed', error: e);
      await WebDav().setEnabled(false);
      _failed = true;
      _message = l10n.setBTestFailed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
        canPop: !_busy,
        child: SettingsDetailScaffold(
          title: Text(l10n.setBSyncServer),
          body: SyncPageBody(
            maxWidth: 640,
            children: [
              SyncPageIntro(
                icon: Icons.dns_rounded,
                title: l10n.setBConnectWebdav,
                description: l10n.setBConnectWebdavDesc,
              ),
              TonalCard(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  onChanged: () {
                    if (_message != null && !_busy) {
                      setState(() => _message = null);
                    }
                  },
                  child: Column(
                    spacing: 20,
                    children: [
                      TextFormField(
                        controller: _url,
                        enabled: !_busy,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: l10n.setBServerAddress,
                          hintText: 'https://example.com/dav/',
                          border: const OutlineInputBorder(),
                          errorMaxLines: 3,
                        ),
                        validator: (value) {
                          final uri = Uri.tryParse(value?.trim() ?? '');
                          if (uri == null ||
                              !['http', 'https'].contains(uri.scheme) ||
                              uri.host.isEmpty) {
                            return l10n.setBUrlInvalid;
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _username,
                        enabled: !_busy,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: l10n.setBUsername,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      TextFormField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: !_passwordVisible,
                        autocorrect: false,
                        enableSuggestions: false,
                        onFieldSubmitted: (_) => _save(),
                        decoration: InputDecoration(
                          labelText: l10n.setBPasswordOrToken,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _passwordVisible ? l10n.setBHidePassword : l10n.setBShowPassword,
                            onPressed: () => setState(
                                () => _passwordVisible = !_passwordVisible),
                            icon: Icon(_passwordVisible
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              StateActionButton(
                onPressed: _busy ? null : _save,
                text: _busy ? l10n.setBTestingConnection : l10n.setBSaveTest,
                icon: Icons.cloud_done_rounded,
              ),
              if (_message != null)
                SyncFeedback(message: _message!, error: _failed, busy: _busy),
              if (_message != null && !_busy && !_failed)
                TextButton(
                  onPressed: () => context.maybePop(),
                  child: Text(l10n.setBBackToSync),
                ),
            ],
          ),
        ),
      );
  }
}

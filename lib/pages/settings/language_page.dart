import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 语言切换页：跟随系统 / 中文 / English（即时生效）
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  void _setLocale(BuildContext context, String locale) {
    GStorage.putSetting(SettingsKeys.appLocale, locale);
    context.read<ThemeProvider>().notifyListeners();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = GStorage.getSetting(SettingsKeys.appLocale).toString();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.languageTitle)),
      body: ListView(
        children: [
          RadioListTile<String>(
            value: 'system',
            groupValue: current,
            title: Text(l10n.languageFollowSystem),
            onChanged: (_) => _setLocale(context, 'system'),
          ),
          RadioListTile<String>(
            value: 'zh',
            groupValue: current,
            title: Text(l10n.languageChinese),
            onChanged: (_) => _setLocale(context, 'zh'),
          ),
          RadioListTile<String>(
            value: 'en',
            groupValue: current,
            title: Text(l10n.languageEnglish),
            onChanged: (_) => _setLocale(context, 'en'),
          ),
        ],
      ),
    );
  }
}

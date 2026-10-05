import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/widget/error_widget.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:url_launcher/url_launcher.dart';

class BangumiMirrorErrorWidget extends StatelessWidget {
  const BangumiMirrorErrorWidget({
    super.key,
    required this.onRetry,
    this.onSettingsReturned,
  });

  final VoidCallback onRetry;
  final VoidCallback? onSettingsReturned;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mirrorEnabled = GStorage.getSetting(SettingsKeys.enableBangumiProxy);

    return GeneralErrorWidget(
      errMsg: mirrorEnabled
          ? l10n.setDMirrorLoadFailEnabled
          : l10n.setDMirrorLoadFailDisabled,
      actions: [
        GeneralErrorButton(
          onPressed: () async {
            await context.pushNamed('/settings/mirror-proxy');
            onSettingsReturned?.call();
          },
          text: l10n.setDMirrorToggle,
        ),
        GeneralErrorButton(
          onPressed: onRetry,
          text: l10n.setDTapRetry,
        ),
        GeneralErrorButton(
          onPressed: () {
            launchUrl(
              Uri.parse('https://qlyyz.xyz/check.php'),
              mode: LaunchMode.externalApplication,
            );
          },
          text: l10n.setDCheckServerStatus,
        ),
      ],
    );
  }
}

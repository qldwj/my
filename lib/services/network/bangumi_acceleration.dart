import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/services/storage/storage.dart';

enum BangumiAcceleration {
  direct,
  ech,
  mirror;

  static BangumiAcceleration get current => switch (GStorage.getSetting(
    SettingsKeys.bangumiAcceleration,
  )) {
    'direct' => direct,
    'ech' => ech,
    'mirror' => mirror,
    _ => mirror,
  };

  String label(AppLocalizations l10n) => switch (this) {
    direct => l10n.setDConnDirect,
    ech => 'ECH',
    mirror => l10n.setDConnMirror,
  };

  String description(AppLocalizations l10n) => switch (this) {
    direct => l10n.setDBangumiDirectDesc,
    ech => l10n.setDBangumiEchDesc,
    mirror => l10n.setDBangumiMirrorDesc,
  };
}

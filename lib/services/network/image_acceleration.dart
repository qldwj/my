import 'package:yhdm/l10n/app_localizations.dart';

enum ImageAcceleration {
  direct,
  ech,
  mirror;

  static ImageAcceleration fromSetting(String value) =>
      values.firstWhere((mode) => mode.name == value, orElse: () => ech);

  /// 显示名称
  String label(AppLocalizations l10n) => switch (this) {
        ImageAcceleration.direct => l10n.setDConnDirect,
        ImageAcceleration.ech => 'ECH',
        ImageAcceleration.mirror => l10n.setDConnMirror,
      };

  /// 说明文字
  String description(AppLocalizations l10n) => switch (this) {
        ImageAcceleration.direct => l10n.setDImageDirectDesc,
        ImageAcceleration.ech => l10n.setDImageEchDesc,
        ImageAcceleration.mirror => l10n.setDImageMirrorDesc,
      };
}

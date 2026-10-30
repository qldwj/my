import 'package:yhdm/services/storage/settings_keys.dart';
import 'package:yhdm/services/storage/storage.dart';

/// 规则仓库加速模式（多镜像源），复刻自 Kazumi 的 RulesMirror。
///
/// 规则仓库主源是 GitHub raw（Kazuminb6Rules），当主源不可达时可切换到
/// AtomGit 镜像或 GitHub 代理（gh-proxy / ghfast）。当前源由用户设置
/// [SettingsKeys.rulesMirror] 决定，未设置时回退旧开关
/// [SettingsKeys.enableGitProxy]（开→AtomGit，关→直连）以保持向后兼容。
enum RulesMirror {
  direct,
  atomgit,
  ghProxy,
  ghfast;

  /// 当前生效的规则仓库源。
  ///
  /// 优先读 [SettingsKeys.rulesMirror]；未设置时与 Kazumi 默认一致：
  /// [SettingsKeys.enableGitProxy] 开启 → ghProxy（gh-proxy.org），否则直连主源。
  static RulesMirror get current {
    final saved = GStorage.getSetting(SettingsKeys.rulesMirror);
    if (saved.isNotEmpty) {
      return switch (saved) {
        'atomgit' => atomgit,
        'ghProxy' => ghProxy,
        'ghfast' => ghfast,
        _ => direct,
      };
    }
    return GStorage.getSetting(SettingsKeys.enableGitProxy) ? ghProxy : direct;
  }

  String label() => switch (this) {
        direct => '直连',
        atomgit => 'AtomGit',
        ghProxy => 'gh-proxy',
        ghfast => 'ghfast',
      };

  String description() => switch (this) {
        direct => '访问 GitHub 主源（raw.githubusercontent.com）',
        atomgit => 'AtomGit 镜像（qldwi/yhdmgz）',
        ghProxy => 'gh-proxy.org 加速（GitHub raw）',
        ghfast => 'ghfast.top 加速（GitHub raw）',
      };
}

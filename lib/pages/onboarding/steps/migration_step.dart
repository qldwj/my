import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/pages/onboarding/onboarding_step_layout.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 🆕 换包名账号迁移步骤（写进首次启动向导）
///
/// 逻辑：
/// - 已登录 / 已做过迁移选择 → 显示「可选」占位，点下一步直接跳过。
/// - 否则询问「是否安装过旧版樱花动漫」：用过 → 填迁移码并迁移；没用过 → 记录 done。
class MigrationStep extends StatefulWidget {
  const MigrationStep({super.key});

  @override
  State<MigrationStep> createState() => _MigrationStepState();
}

class _MigrationStepState extends State<MigrationStep> {
  bool _usedBefore = false; // 用户选择「用过旧版」
  bool _chosen = false; // 是否已做出选择（用过/没用过）
  bool _migrating = false;
  final TextEditingController _codeCtrl = TextEditingController();

  bool get _resolved =>
      AuthService.isLoggedIn ||
      GStorage.getSetting(SettingsKeys.migratePromptDone);

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _choose(bool usedBefore) async {
    setState(() {
      _usedBefore = usedBefore;
      _chosen = true;
    });
    if (!usedBefore) {
      // 没用过旧版：记录 done，以后不再提示
      await GStorage.putSetting(SettingsKeys.migratePromptDone, true);
    }
  }

  Future<void> _migrate() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      KazumiDialog.showToast(message: l10n.migrationCodeEmpty);
      return;
    }
    setState(() => _migrating = true);
    try {
      final done = await AuthService.consumeTransferCode(code);
      if (!mounted) return;
      if (done) {
        KazumiDialog.showToast(message: l10n.migrationSuccess);
        try {
          await SocialService.ensureProfileAfterLogin();
        } catch (_) {}
        await GStorage.putSetting(SettingsKeys.migratePromptDone, true);
        setState(() => _chosen = false);
      } else {
        KazumiDialog.showToast(message: l10n.migrationFailed);
      }
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return OnboardingStepLayout(
      leading: const OnboardingStepIcon(icon: Icons.swap_horiz_rounded),
      title: l10n.migrationTitle,
      subtitle: l10n.migrationSubtitle,
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_resolved)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 40, color: colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        l10n.migrationNotNeeded,
                        style: textTheme.bodyLarge,
                      ),
                    ],
                  ),
                )
              else if (!_chosen)
                Column(
                  children: [
                    Text(
                      l10n.migrationAskOld,
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.migrationOldDesc,
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _choose(true),
                      icon: const Icon(Icons.history_rounded),
                      label: Text(l10n.migrationHaveCode),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _choose(false),
                      child: Text(l10n.migrationSkipNo,
                          style: TextStyle(color: colorScheme.outline)),
                    ),
                  ],
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.migrationEnterCode,
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.migrationCodeDesc,
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _codeCtrl,
                      autofocus: true,
                      maxLength: 8,
                      textCapitalization: TextCapitalization.characters,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: l10n.migrationCodeHint,
                        counterText: '',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _migrating ? null : _migrate,
                      icon: _migrating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(_migrating
                          ? l10n.migrationMigrating
                          : l10n.migrationNow),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _choose(false),
                      child: Text(l10n.migrationSkipLater,
                          style: TextStyle(color: colorScheme.outline)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

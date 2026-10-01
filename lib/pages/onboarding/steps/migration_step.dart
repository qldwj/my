import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
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
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      KazumiDialog.showToast(message: '请输入迁移码');
      return;
    }
    setState(() => _migrating = true);
    try {
      final done = await AuthService.consumeTransferCode(code);
      if (!mounted) return;
      if (done) {
        KazumiDialog.showToast(message: '✅ 登录状态已迁移，无需重新登录');
        try {
          await SocialService.ensureProfileAfterLogin();
        } catch (_) {}
        await GStorage.putSetting(SettingsKeys.migratePromptDone, true);
        setState(() => _chosen = false);
      } else {
        KazumiDialog.showToast(message: '迁移未完成，可稍后重试');
      }
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return OnboardingStepLayout(
      leading: const OnboardingStepIcon(icon: Icons.swap_horiz_rounded),
      title: '账号迁移',
      subtitle: '旧版樱花动漫账号可一键继承，无需重新登录',
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
                        '账号无需迁移，直接下一步即可',
                        style: textTheme.bodyLarge,
                      ),
                    ],
                  ),
                )
              else if (!_chosen)
                Column(
                  children: [
                    Text(
                      '是否安装过旧版樱花动漫？',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '旧版账号可通过「迁移码」直接继承到新版本，'
                      '若你从没用过本应用，选「没用过」即可跳过。',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _choose(true),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('用过，我有迁移码'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _choose(false),
                      child: Text('没用过，跳过',
                          style: TextStyle(color: colorScheme.outline)),
                    ),
                  ],
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '输入迁移码',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '迁移码在旧版 App「账号」页生成，90 秒内有效、只能用一次。',
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
                      decoration: const InputDecoration(
                        hintText: '例如 7KQF2M8X',
                        counterText: '',
                        border: OutlineInputBorder(),
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
                      label: Text(_migrating ? '迁移中…' : '立即迁移'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _choose(false),
                      child: Text('暂不迁移，跳过',
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

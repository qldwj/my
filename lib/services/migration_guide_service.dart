import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 🆕 换包名迁移引导（首次启动）
///
/// 逻辑：
/// - 首次打开（migratePromptDone 未设置）时弹窗询问「是否安装过旧版樱花动漫」。
/// - 选「用过」→ 弹出迁移码输入框。填码并成功即登录；若取消/不填 → 不记录 done，
///   下次启动仍会提示（强制选择）。
/// - 选「没用过」→ 记录 done，以后不再提示。
class MigrationGuideService {
  MigrationGuideService._();

  static Future<void> maybeShow(BuildContext context) async {
    // 已做过选择：不再提示
    if (GStorage.getSetting(SettingsKeys.migratePromptDone)) {
      return;
    }
    // 已登录说明无需迁移
    if (AuthService.isLoggedIn) {
      await GStorage.putSetting(SettingsKeys.migratePromptDone, true);
      return;
    }
    if (!context.mounted) return;

    final usedBefore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('是否安装过旧版樱花动漫？'),
        content: const Text(
          '旧版账号可通过「迁移码」直接继承到新版本，无需重新登录。\n'
          '如果你之前没有用过本应用，选择「没用过」即可，以后不会再询问。',
          textAlign: TextAlign.left,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('没用过'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('用过'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    if (usedBefore != true) {
      // 选「没用过」：以后不再提示
      await GStorage.putSetting(SettingsKeys.migratePromptDone, true);
      return;
    }

    // 选「用过」：必须填迁移码，否则不记录 done（下次继续提示）
    await _promptTransferCode(context);
  }

  /// 输入迁移码并尝试迁移登录态。
  /// 返回是否成功；取消/失败返回 false（不记录 done）。
  static Future<bool> _promptTransferCode(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('我有迁移码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 8,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  hintText: '例如 7KQF2M8X', counterText: ''),
            ),
            const SizedBox(height: 4),
            Text(
              '迁移码在旧版 App「账号」页生成，10 分钟内有效、只能用一次。\n'
              '若暂无迁移码，可先跳过，下次启动会再次询问。',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(ctx).colorScheme.outline),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('跳过')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('立即迁移')),
        ],
      ),
    );
    final code = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || code.isEmpty || !context.mounted) {
      // 取消/跳过或没填码：不记录 done，下次继续提示
      return false;
    }
    final done = await AuthService.consumeTransferCode(code);
    if (!context.mounted) return done;
    if (done) {
      KazumiDialog.showToast(message: '✅ 登录状态已迁移，无需重新登录');
      try {
        await SocialService.ensureProfileAfterLogin();
      } catch (_) {}
      await GStorage.putSetting(SettingsKeys.migratePromptDone, true);
    } else {
      // 迁移失败（码无效/网络错误）：不记录 done，下次继续提示
      KazumiDialog.showToast(message: '迁移未完成，可稍后重试');
    }
    return done;
  }
}

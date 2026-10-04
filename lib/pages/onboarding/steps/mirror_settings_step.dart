import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/network_mirror_settings.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/pages/onboarding/onboarding_step_layout.dart';

/// 引导页：网络镜像（番剧条目镜像 / 规则仓库镜像 / 图片加速）
class MirrorSettingsStep extends StatelessWidget {
  const MirrorSettingsStep({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepLayout(
      leading: const OnboardingStepIcon(icon: Icons.public_rounded),
      title: l10n.mirrorTitle,
      subtitle: l10n.mirrorSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NetworkMirrorSettings(margin: EdgeInsetsDirectional.zero),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.mirrorLaterHint,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

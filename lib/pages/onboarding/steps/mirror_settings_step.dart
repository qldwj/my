import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/network_mirror_settings.dart';
import 'package:kazumi/pages/onboarding/onboarding_step_layout.dart';

/// 引导页：网络镜像（番剧条目镜像 / 规则仓库镜像 / 图片加速）
class MirrorSettingsStep extends StatelessWidget {
  const MirrorSettingsStep({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OnboardingStepLayout(
      leading: const OnboardingStepIcon(icon: Icons.public_rounded),
      title: '网络镜像',
      subtitle: '中国大陆用户推荐启用，提升访问速度。图片默认使用 ECH 加速。',
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
                    '可稍后在 设置 → 网络设置 中修改',
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

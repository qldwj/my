import 'package:flutter/material.dart';

import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/pages/about/about_widgets.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/l10n/app_localizations.dart';

class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsDetailScaffold(
      title: Text(l10n.setCAcknowledgements),
      body: AboutContent(
        children: [
          ContentSection.group(
            title: l10n.setCContribution,
            children: [
              AboutLinkTile(
                icon: Icons.people_outline_rounded,
                title: l10n.setCContributors,
                url: '${ApiEndpoints.sourceUrl}/graphs/contributors',
              ),
              AboutLinkTile(
                icon: Icons.brush_rounded,
                title: l10n.setCIconAuthor,
                subtitle: 'Pixiv',
                url: ApiEndpoints.iconUrl,
              ),
            ],
          ),
          const SizedBox(height: 24),
          ContentSection.group(
            title: l10n.setCServices,
            children: [
              AboutLinkTile(
                icon: Icons.menu_book_rounded,
                title: 'Bangumi',
                subtitle: l10n.setCAnimeInfo,
                url: ApiEndpoints.bangumiIndex,
              ),
              AboutLinkTile(
                icon: Icons.subtitles_rounded,
                title: '弹弹play',
                subtitle: l10n.setCDanmaku,
                url: ApiEndpoints.dandanIndex,
              ),
              AboutLinkTile(
                icon: Icons.image_search_rounded,
                title: 'trace.moe',
                subtitle: l10n.setCReverseSearch,
                url: 'https://trace.moe',
              ),
            ],
          ),
          const SizedBox(height: 24),
          ContentSection.group(
            title: l10n.setCOpenSourceProjects,
            children: [
              AboutLinkTile(
                icon: Icons.flutter_dash_rounded,
                title: 'Flutter',
                subtitle: l10n.setCAppFramework,
                url: 'https://flutter.dev',
              ),
              AboutLinkTile(
                icon: Icons.play_circle_outline_rounded,
                title: 'media-kit',
                subtitle: l10n.setCVideoPlayback,
                url: 'https://github.com/media-kit/media-kit',
              ),
              AboutLinkTile(
                icon: Icons.auto_awesome_rounded,
                title: 'Anime4K',
                subtitle: l10n.setCRealTimeUpscaling,
                url: 'https://github.com/bloc97/Anime4K',
              ),
              AboutLinkTile(
                icon: Icons.sync_rounded,
                title: 'Syncplay',
                subtitle: l10n.setCPlaybackSync,
                url: 'https://github.com/Syncplay/syncplay',
              ),
              AboutLinkTile(
                icon: Icons.account_tree_rounded,
                title: 'XpathSelector',
                subtitle: l10n.setCXpathParsing,
                url: 'https://github.com/simonkimi/xpath_selector',
              ),
              AboutLinkTile(
                icon: Icons.video_settings_rounded,
                title: 'avbuild',
                subtitle: l10n.setCNonStandardStream,
                url: 'https://github.com/wang-bin/avbuild',
              ),
              AboutLinkTile(
                icon: Icons.storage_rounded,
                title: 'Hive CE',
                subtitle: l10n.setCLocalStorage,
                url: 'https://github.com/IO-Design-Team/hive_ce',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

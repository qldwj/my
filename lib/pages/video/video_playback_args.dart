import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/modules/download/download_module.dart';
import 'package:yhdm/modules/roads/road_module.dart';
import 'package:yhdm/plugins/plugins.dart';

/// Route arguments for '/video/'. Entry points hand playback context over
/// through the route instead of pre-filling a shared controller, which lets
/// [VideoPageController] live and die with the route.
sealed class VideoPlaybackArgs {
  const VideoPlaybackArgs({required this.bangumiItem});

  final BangumiItem bangumiItem;
}

class OnlineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OnlineVideoPlaybackArgs({
    required super.bangumiItem,
    required this.plugin,
    required this.title,
    required this.src,
    required this.roads,
  });

  final Plugin plugin;
  final String title;
  final String src;
  final List<Road> roads;
}

/// 自动解析模式：详情页点「开始观看」直接进播放页，
/// 播放页内自动完成 搜索源 → 评分选源 → 解析分集 → 播放。
class AutoResolveVideoPlaybackArgs extends VideoPlaybackArgs {
  const AutoResolveVideoPlaybackArgs({
    required super.bangumiItem,
  });
}

class OfflineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OfflineVideoPlaybackArgs({
    required super.bangumiItem,
    required this.pluginName,
    required this.episodeNumber,
    required this.road,
    required this.downloadedEpisodes,
  });

  final String pluginName;
  final int episodeNumber;
  final int road;
  final List<DownloadEpisode> downloadedEpisodes;
}

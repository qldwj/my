import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/plugins/plugins.dart';

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

/// 详情页「开始观看」直接进入播放页、在播放页内自动搜索并选择最快可用源的入口。
/// 不携带 plugin/src/roads，播放页首帧通过 [VideoPageController.autoResolveAndPlay]
/// 并发检索所有规则并自动选择。
class AutoOnlineVideoPlaybackArgs extends VideoPlaybackArgs {
  const AutoOnlineVideoPlaybackArgs({
    required super.bangumiItem,
    this.episode = 1,
  });

  /// 目标集数（1 起），默认第 1 集。
  final int episode;
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

import 'dart:convert';
import 'dart:io';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:path_provider/path_provider.dart';

/// 连播队列中的一项（"稍后看"）
///
/// 保存播放一集所需的完整上下文：条目 + 插件 + 详情页地址 + 全部分集线路。
/// 播放时通过 [Plugin.fromJson] 恢复插件实例，构造
/// `OnlineVideoPlaybackArgs` 打开新的播放页。
class PlayQueueItem {
  final BangumiItem bangumiItem;
  final Plugin plugin;
  final String title;
  final String src;
  final List<Road> roads;
  final int episode;
  final int road;
  final DateTime addedTime;

  PlayQueueItem({
    required this.bangumiItem,
    required this.plugin,
    required this.title,
    required this.src,
    required this.roads,
    required this.episode,
    required this.road,
    required this.addedTime,
  });

  Map<String, dynamic> toJson() => {
        'bangumi_item': _bangumiToJson(bangumiItem),
        'plugin': plugin.toJson(),
        'title': title,
        'src': src,
        'roads': roads
            .map((r) => {
                  'name': r.name,
                  'data': r.data,
                  'identifier': r.identifier,
                })
            .toList(),
        'episode': episode,
        'road': road,
        'added_time': addedTime.toIso8601String(),
      };

  factory PlayQueueItem.fromJson(Map<String, dynamic> json) {
    return PlayQueueItem(
      bangumiItem: _bangumiFromJson(
          json['bangumi_item'] as Map<String, dynamic>? ?? const {}),
      plugin: Plugin.fromJson(
          json['plugin'] as Map<String, dynamic>? ?? const {}),
      title: json['title'] as String? ?? '',
      src: json['src'] as String? ?? '',
      roads: (json['roads'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((r) => Road(
                name: r['name'] as String? ?? '',
                data: (r['data'] as List? ?? const [])
                    .whereType<String>()
                    .toList(),
                identifier: (r['identifier'] as List? ?? const [])
                    .whereType<String>()
                    .toList(),
              ))
          .toList(),
      episode: json['episode'] as int? ?? 1,
      road: json['road'] as int? ?? 0,
      addedTime:
          DateTime.tryParse(json['added_time'] as String? ?? '') ??
              DateTime.now(),
    );
  }

  /// 展示名称：番剧名 + 集数
  String get displayName {
    final name =
        bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;
    final roadIndex = road.clamp(0, roads.length - 1);
    final roadData = roads.isEmpty ? null : roads[roadIndex];
    final epName = (roadData != null && episode - 1 < roadData.identifier.length)
        ? roadData.identifier[episode - 1]
        : '第$episode集';
    return '$name · $epName';
  }

  static Map<String, dynamic> _bangumiToJson(BangumiItem item) => {
        'id': item.id,
        'name': item.name,
        'name_cn': item.nameCn,
        'summary': item.summary,
        'images': item.images,
        'rating': item.ratingScore,
      };

  static BangumiItem _bangumiFromJson(Map<String, dynamic> json) {
    return BangumiItem(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      nameCn: json['name_cn'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      images: (json['images'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
      tags: [],
      alias: [],
      ratingScore: (json['rating'] as num?)?.toDouble() ?? 0.0,
      type: 0,
      airDate: '',
      airWeekday: 0,
      rank: 0,
      votes: 0,
      votesCount: [],
      info: '',
    );
  }
}

/// 连播队列服务（JSON 文件持久化）
///
/// 用途：
/// - 把"当前正在看的一集"加入队列
/// - 当前番剧最后一集播放完毕时，自动从队列取下一项继续播放
class PlayQueueService {
  PlayQueueService._();

  static final PlayQueueService instance = PlayQueueService._();

  final List<PlayQueueItem> _items = [];
  bool _loaded = false;

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/play_queue.json');
  }

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final file = await _file;
      if (await file.exists()) {
        final data = json.decode(await file.readAsString()) as List;
        _items
          ..clear()
          ..addAll(data
              .whereType<Map<String, dynamic>>()
              .map(PlayQueueItem.fromJson));
      }
    } catch (e) {
      KazumiLogger().w('PlayQueue: load failed', error: e);
    }
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      final file = await _file;
      await file.writeAsString(
        json.encode(_items.map((i) => i.toJson()).toList()),
      );
    } catch (e) {
      KazumiLogger().e('PlayQueue: save failed', error: e);
    }
  }

  int get length => _items.length;

  /// 全部队列项（副本）
  Future<List<PlayQueueItem>> getAll() async {
    await _load();
    return List.from(_items);
  }

  /// 加入队列（同一番剧同一集去重，返回是否新增）
  Future<bool> add(PlayQueueItem item) async {
    await _load();
    for (final existing in _items) {
      if (existing.bangumiItem.id == item.bangumiItem.id &&
          existing.episode == item.episode &&
          existing.road == item.road) {
        return false;
      }
    }
    _items.add(item);
    await _save();
    return true;
  }

  Future<void> removeAt(int index) async {
    await _load();
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      await _save();
    }
  }

  Future<void> clear() async {
    await _load();
    _items.clear();
    await _save();
  }

  /// 弹出第一项（自动连播时取用），队列为空返回 null
  Future<PlayQueueItem?> takeNext() async {
    await _load();
    if (_items.isEmpty) return null;
    final item = _items.removeAt(0);
    await _save();
    return item;
  }
}

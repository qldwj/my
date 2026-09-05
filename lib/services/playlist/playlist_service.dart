import 'dart:convert';
import 'dart:io';
import 'package:kazumi/modules/playlist/playlist_module.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:path_provider/path_provider.dart';

/// 播放列表服务（JSON 文件持久化）
class PlaylistService {
  static final PlaylistService _instance = PlaylistService._internal();
  factory PlaylistService() => _instance;
  PlaylistService._internal();

  List<Playlist> _playlists = [];
  final Map<String, List<PlaylistItem>> _itemsMap = {};
  bool _loaded = false;

  Future<String> get _storagePath async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> _savePlaylists() async {
    try {
      final path = await _storagePath;
      final file = File('$path/playlists.json');
      await file.writeAsString(
        json.encode(_playlists.map((p) => p.toJson()).toList()),
      );
    } catch (e) {
      KazumiLogger().e('Playlist: save failed', error: e);
    }
  }

  Future<void> _saveItems(String playlistId) async {
    try {
      final path = await _storagePath;
      final items = _itemsMap[playlistId] ?? [];
      final file = File('$path/playlist_items_$playlistId.json');
      await file.writeAsString(
        json.encode(items.map((i) => i.toJson()).toList()),
      );
    } catch (e) {
      KazumiLogger().e('Playlist: save items failed', error: e);
    }
  }

  Future<void> _loadPlaylists() async {
    if (_loaded) return;
    try {
      final path = await _storagePath;
      // 加载播放列表
      final file = File('$path/playlists.json');
      if (await file.exists()) {
        final data = json.decode(await file.readAsString()) as List;
        _playlists = data
            .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      // 加载各列表的项（延迟加载）
      for (final playlist in _playlists) {
        final itemsFile = File('$path/playlist_items_${playlist.id}.json');
        if (await itemsFile.exists()) {
          final data = json.decode(await itemsFile.readAsString()) as List;
          _itemsMap[playlist.id] = data
              .map((e) => PlaylistItem.fromJson(e as Map<String, dynamic>))
              .toList();
        } else {
          _itemsMap[playlist.id] = [];
        }
      }
      _loaded = true;
    } catch (e) {
      KazumiLogger().e('Playlist: load failed', error: e);
      _loaded = true;
    }
  }

  /// 确保已加载
  Future<void> ensureLoaded() async {
    if (!_loaded) await _loadPlaylists();
  }

  /// 获取所有播放列表
  Future<List<Playlist>> getPlaylists() async {
    await ensureLoaded();
    return List.from(_playlists);
  }

  /// 创建播放列表
  Future<void> createPlaylist(String name) async {
    await ensureLoaded();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();
    _playlists.add(Playlist(
      id: id,
      name: name,
      createdTime: now,
      updatedTime: now,
    ));
    _itemsMap[id] = [];
    await _savePlaylists();
  }

  /// 删除播放列表
  Future<void> deletePlaylist(String playlistId) async {
    await ensureLoaded();
    _playlists.removeWhere((p) => p.id == playlistId);
    _itemsMap.remove(playlistId);
    await _savePlaylists();
    try {
      final path = await _storagePath;
      final file = File('$path/playlist_items_$playlistId.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 添加剧集到播放列表
  Future<void> addToPlaylist(String playlistId, PlaylistItem item) async {
    await ensureLoaded();
    _itemsMap.putIfAbsent(playlistId, () => []);
    _itemsMap[playlistId]!.add(item);
    final playlist = _playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => Playlist(id: '', name: '', createdTime: DateTime.now(), updatedTime: DateTime.now()),
    );
    if (playlist.id.isNotEmpty) {
      playlist.updatedTime = DateTime.now();
    }
    await _savePlaylists();
    await _saveItems(playlistId);
  }

  /// 获取播放列表中的项
  Future<List<PlaylistItem>> getPlaylistItems(String playlistId) async {
    await ensureLoaded();
    return List.from(_itemsMap[playlistId] ?? []);
  }

  /// 从播放列表移除项
  Future<void> removeFromPlaylist(String playlistId, int index) async {
    await ensureLoaded();
    final items = _itemsMap[playlistId];
    if (items != null && index < items.length) {
      items.removeAt(index);
      await _saveItems(playlistId);
    }
  }
}

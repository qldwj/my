import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/modules/playlist/playlist_module.dart';
import 'package:kazumi/services/playlist/playlist_service.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';

/// 播放列表管理页面
class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  final PlaylistService _service = PlaylistService();
  List<Playlist> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _loading = true);
    final playlists = await _service.getPlaylists();
    if (mounted) {
      setState(() {
        _playlists = playlists;
        _loading = false;
      });
    }
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建播放列表'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入播放列表名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await _service.createPlaylist(name);
      await _loadPlaylists();
    }
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除播放列表'),
        content: Text('确定删除「${playlist.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _service.deletePlaylist(playlist.id);
      await _loadPlaylists();
      if (mounted) KazumiDialog.showToast(message: '已删除');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: SysAppBar(
        title: const Text('播放列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '新建播放列表',
            onPressed: _createPlaylist,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.playlist_play_rounded, size: 64,
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
                      const SizedBox(height: 16),
                      Text('还没有播放列表', style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _createPlaylist,
                        icon: const Icon(Icons.add),
                        label: const Text('创建第一个播放列表'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    return FutureBuilder<List<PlaylistItem>>(
                      future: _service.getPlaylistItems(playlist.id),
                      builder: (ctx, snapshot) {
                        final itemCount = snapshot.data?.length ?? 0;
                        return Card(
                          child: ListTile(
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.playlist_play,
                                  color: theme.colorScheme.primary),
                            ),
                            title: Text(playlist.name),
                            subtitle: Text(
                                '$itemCount 集 · ${_formatDate(playlist.updatedTime)}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () => _deletePlaylist(playlist),
                            ),
                            onTap: () => _showPlaylistDetail(playlist),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }

  void _showPlaylistDetail(Playlist playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _PlaylistDetailPage(
          playlist: playlist,
          service: _service,
        ),
      ),
    ).then((_) => _loadPlaylists());
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 播放列表详情页
class _PlaylistDetailPage extends StatefulWidget {
  final Playlist playlist;
  final PlaylistService service;

  const _PlaylistDetailPage({
    required this.playlist,
    required this.service,
  });

  @override
  State<_PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<_PlaylistDetailPage> {
  List<PlaylistItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.service.getPlaylistItems(widget.playlist.id);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: SysAppBar(title: Text(widget.playlist.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.playlist_play_rounded, size: 64,
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
                      const SizedBox(height: 16),
                      Text('列表为空', style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 8),
                      Text('在播放页面可以将剧集添加到播放列表',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text('${index + 1}',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                )),
                          ),
                        ),
                        title: Text(
                          item.bangumiItem.nameCn.isNotEmpty
                              ? item.bangumiItem.nameCn
                              : item.bangumiItem.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle:
                            Text('第${item.episodeNumber}集 · ${item.episodeTitle}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red),
                          onPressed: () async {
                            await widget.service
                                .removeFromPlaylist(widget.playlist.id, index);
                            await _load();
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

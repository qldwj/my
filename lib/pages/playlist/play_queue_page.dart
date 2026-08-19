import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/playlist/play_queue_service.dart';

/// 连播队列页（"稍后看"）
///
/// - 展示队列中待连播的剧集
/// - 点击立即播放（打开播放页并跳到记录的那一集）
/// - 当前番剧最后一集播完时自动接播队列第一项
class PlayQueuePage extends StatefulWidget {
  const PlayQueuePage({super.key});

  @override
  State<PlayQueuePage> createState() => _PlayQueuePageState();
}

class _PlayQueuePageState extends State<PlayQueuePage> {
  List<PlayQueueItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await PlayQueueService.instance.getAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _playItem(PlayQueueItem item) async {
    // 让新播放页从记录的集数开始播放
    VideoPageController.pendingQueueEpisode = (item.episode, item.road);
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    await Navigator.of(navContext).pushNamed(
      '/video/',
      arguments: OnlineVideoPlaybackArgs(
        bangumiItem: item.bangumiItem,
        plugin: item.plugin,
        title: item.title,
        src: item.src,
        roads: item.roads,
      ),
    );
    // 从队列页返回后刷新（可能播放完了自动弹出下一项）
    _reload();
  }

  Future<void> _removeItem(int index) async {
    await PlayQueueService.instance.removeAt(index);
    _reload();
  }

  Future<void> _clearAll() async {
    final confirm = await KazumiDialog.show<bool>(
      builder: (context) => AlertDialog(
        title: const Text('清空连播队列'),
        content: const Text('确定清空队列中所有待连播剧集？'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await PlayQueueService.instance.clear();
    _reload();
    if (mounted) KazumiDialog.showToast(message: '队列已清空');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('连播队列'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: '清空队列',
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: GeneralEmptyState(
                    icon: Icons.playlist_play_rounded,
                    title: '队列为空',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: NetworkImgLayer(
                            width: 48,
                            height: 64,
                            src: item.bangumiItem.images['large'] ?? '',
                          ),
                        ),
                        title: Text(
                          item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${item.plugin.name} · ${item.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: colorScheme.outline),
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.close,
                              size: 20, color: colorScheme.outline),
                          tooltip: '移出队列',
                          onPressed: () => _removeItem(index),
                        ),
                        onTap: () => _playItem(item),
                      ),
                    );
                  },
                ),
    );
  }
}

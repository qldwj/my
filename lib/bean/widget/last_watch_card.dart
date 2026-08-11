import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/device.dart';

/// 首页左下角"上次观看"弹窗
///
/// 点击后直接跳转到播放器继续观看（和历史记录卡片行为一致）
class LastWatchCard extends StatefulWidget {
  final History history;
  final VoidCallback onDismiss;

  const LastWatchCard({
    super.key,
    required this.history,
    required this.onDismiss,
  });

  @override
  State<LastWatchCard> createState() => _LastWatchCardState();
}

class _LastWatchCardState extends State<LastWatchCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  // 注入插件控制器（与历史卡片一致）
  final PluginsController _pluginsController = inject<PluginsController>();

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
    ));

    _animController.forward();

    // 5秒后自动向左滑出关闭
    _dismissTimer = Timer(const Duration(seconds: 5), () {
      _slideOut();
    });
  }

  void _slideOut() {
    _animController.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  String _formatProgress(Duration? progress) {
    if (progress == null || progress == Duration.zero) return '未开始';
    final hours = progress.inHours;
    final minutes = progress.inMinutes.remainder(60);
    final seconds = progress.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _displayName(BangumiItem item) {
    return item.nameCn.isNotEmpty ? item.nameCn : item.name;
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.history;
    final bangumi = history.bangumiItem;
    final progress = history.progresses[history.lastWatchEpisode];
    final theme = Theme.of(context);

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 80),
          child: GestureDetector(
            onTap: () {
              _dismissTimer?.cancel();
              _resumePlayback(context);
            },
            child: Container(
              width: 310,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                // 樱花粉背景
                color: const Color(0xFFFFB7C5),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 播放图标
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: const Color(0xFFE75480),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 文字内容
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '上次看到',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withAlpha(200),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _displayName(bangumi),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '第${history.lastWatchEpisode}集 · ${_formatProgress(progress?.progress)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withAlpha(200),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 设置按钮
                  GestureDetector(
                    onTap: () {
                      _dismissTimer?.cancel();
                      _navigateToSettings(context);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(180),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.settings_rounded,
                        size: 18,
                        color: const Color(0xFFE75480),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 箭头
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withAlpha(180),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 跳转到播放设置页
  void _navigateToSettings(BuildContext context) {
    context.pushNamed('/settings/player');
    widget.onDismiss();
  }

  /// 和历史记录卡片一样：直接跳转到播放器继续观看
  Future<void> _resumePlayback(BuildContext context) async {
    final history = widget.history;

    // 显示加载中
    KazumiDialog.showLoading(
      msg: '获取播放信息中',
      barrierDismissible: isDesktop(),
    );

    try {
      if (history.entryKind == HistoryEntryKind.offline) {
        // === 离线播放 ===
        await _playOffline(context, history);
      } else {
        // === 在线播放 ===
        await _playOnline(context, history);
      }
    } catch (e, stackTrace) {
      KazumiLogger().e('LastWatchCard: 播放失败', error: e, stackTrace: stackTrace);
      KazumiDialog.dismiss();
      if (mounted) {
        KazumiDialog.showToast(message: '无法继续观看，请重试');
        // 降级：跳转到番剧详情页
        context.pushNamed('/info/', arguments: history.bangumiItem);
      }
    }
  }

  /// 在线播放
  Future<void> _playOnline(BuildContext context, History history) async {
    if (history.lastSrc.isEmpty) {
      KazumiDialog.dismiss();
      KazumiDialog.showToast(message: '播放源不可用');
      return;
    }

    // 查找插件
    final pluginsController = _pluginsController;
    Plugin? targetPlugin;
    for (final plugin in pluginsController.pluginList) {
      if (plugin.name == history.adapterName) {
        targetPlugin = plugin;
        break;
      }
    }

    if (targetPlugin == null) {
      KazumiDialog.dismiss();
      if (mounted) {
        KazumiDialog.showToast(message: '未找到对应规则，跳转详情页');
        context.pushNamed('/info/', arguments: history.bangumiItem);
      }
      return;
    }

    try {
      // 查询剧集路线
      final roads = await targetPlugin.queryChapterRoads(
        history.lastSrc,
      );

      if (roads.isEmpty) {
        KazumiDialog.dismiss();
        if (mounted) {
          KazumiDialog.showToast(message: '未获取到剧集信息');
          context.pushNamed('/info/', arguments: history.bangumiItem);
        }
        return;
      }

      KazumiDialog.dismiss();

      if (!mounted) return;

      // 构造播放参数
      final args = OnlineVideoPlaybackArgs(
        bangumiItem: history.bangumiItem,
        plugin: targetPlugin,
        title: history.bangumiItem.nameCn == ''
            ? history.bangumiItem.name
            : history.bangumiItem.nameCn,
        src: history.lastSrc,
        roads: roads,
      );

      // 跳转到播放器
      context.pushNamed('/video/', arguments: args);
      widget.onDismiss();
    } catch (e) {
      KazumiLogger().w('LastWatchCard: 查询剧集失败', error: e);
      KazumiDialog.dismiss();
      if (mounted) {
        KazumiDialog.showToast(message: '获取剧集失败，跳转详情页');
        context.pushNamed('/info/', arguments: history.bangumiItem);
      }
    }
  }

  /// 离线播放
  Future<void> _playOffline(BuildContext context, History history) async {
    // 对于离线播放，简化为跳转到详情页
    // 完整实现需要 DownloadController 的支持
    KazumiDialog.dismiss();
    if (mounted) {
      context.pushNamed('/info/', arguments: history.bangumiItem);
      widget.onDismiss();
    }
  }
}

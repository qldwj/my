import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/playlist/playlist_module.dart';
import 'package:kazumi/services/playlist/playlist_service.dart';
import 'package:kazumi/pages/info/rating_review_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/pages/my/friend_picker.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/bean/card/bangumi_info_card.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/pages/info/info_tabview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/nsfw_filter.dart';

class InfoPage extends StatefulWidget {
  const InfoPage({
    super.key,
    required this.inputBangumiItem,
    required this.infoController,
    required this.pluginsController,
  });

  final BangumiItem inputBangumiItem;
  final InfoController infoController;
  final PluginsController pluginsController;

  /// 深链带入的待播放集数（分享链接 ?ep=N，由 DeepLinkService 设置）
  static int? pendingEpisodeId;
  static int? pendingEpisode;

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> with TickerProviderStateMixin {
  static const List<String> _infoTabs = <String>[
    '概览',
    '吐槽',
    '角色',
    '相关',
    '制作人员',
  ];
  static const int _commentsTabIndex = 1;
  static const Duration _minimumBangumiInfoLoadingDuration =
      Duration(milliseconds: 600);

  InfoController get infoController => widget.infoController;
  PluginsController get pluginsController => widget.pluginsController;
  late TabController sourceTabController;
  late TabController infoTabController;
  late bool showRating;

  bool commentsIsLoading = false;
  bool charactersIsLoading = false;
  bool commentsQueryTimeout = false;
  bool commentsIsEmpty = false;
  bool charactersQueryTimeout = false;
  bool charactersIsEmpty = false;
  bool staffIsLoading = false;
  bool staffQueryTimeout = false;
  bool staffIsEmpty = false;
  bool _showBangumiInfoSkeleton = false;
  int _fabTabIndex = 0;

  BangumiItem get inputBangumiIten => widget.inputBangumiItem;

  bool get _isShowingBangumiInfoSkeleton =>
      infoController.isLoading || _showBangumiInfoSkeleton;

  bool _needsBangumiInfoRefresh(BangumiItem bangumiItem) {
    final votesCount = bangumiItem.votesCount;
    final missingVoteDistribution =
        votesCount.isEmpty || bangumiItem.votes <= 0 || votesCount.length < 10;
    return bangumiItem.summary == '' || missingVoteDistribution;
  }

  Future<void> loadCharacters() async {
    if (charactersIsLoading) return;
    setState(() {
      charactersIsLoading = true;
      charactersQueryTimeout = false;
      charactersIsEmpty = false;
    });
    try {
      await infoController
          .queryBangumiCharactersByID(infoController.bangumiItem.id);
      if (mounted) {
        setState(() {
          charactersIsLoading = false;
          if (infoController.characterList.isEmpty) {
            charactersIsEmpty = true;
          }
        });
      }
    } catch (e) {
      KazumiLogger().e('InfoPage: failed to load characters', error: e);
      if (mounted) {
        setState(() {
          charactersIsLoading = false;
          charactersQueryTimeout = true;
        });
      }
    }
  }

  Future<void> loadStaff() async {
    if (staffIsLoading) return;
    setState(() {
      staffIsLoading = true;
      staffQueryTimeout = false;
      staffIsEmpty = false;
    });
    try {
      await infoController
          .queryBangumiStaffsByID(infoController.bangumiItem.id);
      if (mounted) {
        setState(() {
          staffIsLoading = false;
          if (infoController.staffList.isEmpty) {
            staffIsEmpty = true;
          }
        });
      }
    } catch (e) {
      KazumiLogger().e('InfoPage: failed to load staff', error: e);
      if (mounted) {
        setState(() {
          staffIsLoading = false;
          staffQueryTimeout = true;
        });
      }
    }
  }

  Future<void> loadMoreComments({bool loadMore = false}) async {
    if (commentsIsLoading) return;
    setState(() {
      commentsIsLoading = true;
      commentsQueryTimeout = false;
      commentsIsEmpty = false;
    });
    try {
      await infoController.queryBangumiCommentsByID(
          infoController.bangumiItem.id,
          refresh: !loadMore);
      if (mounted) {
        setState(() {
          commentsIsLoading = false;
          if (infoController.commentsList.isEmpty &&
              !(infoController.bangumiItem.interest?.hasReviewContent ??
                  false)) {
            commentsIsEmpty = true;
          }
        });
      }
    } catch (e) {
      KazumiLogger().e('InfoPage: failed to load comments', error: e);
      if (mounted) {
        setState(() {
          commentsIsLoading = false;
          commentsQueryTimeout = true;
        });
      }
    }
  }

  void onBangumiRatingTap() {
    final bangumiToken = GStorage.getSetting(SettingsKeys.bangumiAccessToken).toString().trim();
    final isLoggedIn = AuthService.isLoggedIn;
    
    // 两个都没登录，不能打开
    if (bangumiToken.isEmpty && !isLoggedIn) {
      KazumiDialog.showToast(message: '请先登录 Bangumi 或樱花动漫账号');
      return;
    }

    final localType = infoController.collectController.getCollectType(infoController.bangumiItem);
    if (localType == 0) {
      KazumiDialog.showToast(message: '请先追番后再发表评价');
      return;
    }

    // 🆕 选择发送到哪里
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text('发表吐槽', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (bangumiToken.isNotEmpty)
                ListTile(
                  leading: Image.asset('assets/images/icons/bangumi.png', width: 28, height: 28),
                  title: const Text('发送到 Bangumi'),
                  subtitle: const Text('同步到 Bangumi 评分系统'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    _submitToBangumi(localType);
                  },
                ),
              if (isLoggedIn)
                ListTile(
                  leading: const Icon(Icons.comment, color: Colors.blue),
                  title: const Text('发送到樱花动漫'),
                  subtitle: const Text('发表到樱花动漫评论系统'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    _submitToServer(localType);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _submitToBangumi(int localType) {
    KazumiDialog.show(
      builder: (context) => RatingReviewDialog(
        bangumiItem: infoController.bangumiItem,
        onSubmit: (data) async {
          final updated = await infoController.rateBangumi(data, localType: localType);
          if (updated && mounted) setState(() {});
          return updated;
        },
      ),
    );
  }

  void _submitToServer(int localType) {
    var serverRating = 0;
    final commentController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('发表吐槽'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('评分: '),
                      for (int i = 1; i <= 10; i++)
                        GestureDetector(
                          onTap: () => setDialogState(() => serverRating = i),
                          child: Icon(
                            i <= serverRating ? Icons.star : Icons.star_outline,
                            color: i <= serverRating ? Colors.amber : Colors.grey,
                            size: 28,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: '写下你的吐槽...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                FilledButton(
                  onPressed: () async {
                    final text = commentController.text.trim();
                    if (text.isEmpty && serverRating == 0) {
                      KazumiDialog.showToast(message: '请输入评分或评论');
                      return;
                    }
                    Navigator.pop(ctx);
                    try {
                      final user = SocialService.myProfile;
                      final res = await http.post(
                        Uri.parse('https://qlyyz.xyz/api/comment.php?action=add'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'subjectId': infoController.bangumiItem.id,
                          'episode': 0,
                          'text': text,
                          'sender': user?.nickname ?? '匿名',
                          'uid': user?.uid ?? '',
                          'avatar': user?.avatar ?? '',
                          'rating': serverRating,
                        }),
                      );
                      if (res.statusCode == 200) {
                        KazumiDialog.showToast(message: '吐槽发表成功');
                      } else {
                        KazumiDialog.showToast(message: '发表失败');
                      }
                    } catch (e) {
                      KazumiDialog.showToast(message: '网络错误: $e');
                    }
                  },
                  child: const Text('发表'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // ⭐ 深链带入集数时，首帧后自动弹出选集面板
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoOpenSourceFromDeepLink();
    });
    infoController.bangumiItem = inputBangumiIten;
    infoController.characterList.clear();
    infoController.clearComments();
    infoController.staffList.clear();
    infoController.pluginSearchResponseList.clear();
    // Search results can miss rating distribution or summaries, so fill those
    // fields without replacing image URLs that are already rendered.
    if (_needsBangumiInfoRefresh(infoController.bangumiItem)) {
      _showBangumiInfoSkeleton = true;
      queryBangumiInfoByID(
        infoController.bangumiItem.id,
        type: 'attach',
        enforceMinimumLoadingDuration: true,
      );
    }
    sourceTabController =
        TabController(length: pluginsController.pluginList.length, vsync: this);
    infoTabController = TabController(length: _infoTabs.length, vsync: this);
    _fabTabIndex = infoTabController.index;
    showRating = GStorage.getSetting(SettingsKeys.showRating);
    infoTabController.addListener(onInfoTabChanged);
    infoTabController.addListener(_syncFabTabIndex);
    infoTabController.animation?.addListener(_syncFabTabIndex);
  }

  /// 深链（分享链接 ?ep=N）自动弹出选集面板
  void _maybeAutoOpenSourceFromDeepLink() {
    final id = InfoPage.pendingEpisodeId;
    final ep = InfoPage.pendingEpisode;
    if (id == null || ep == null) return;
    if (id != infoController.bangumiItem.id) return;
    InfoPage.pendingEpisodeId = null;
    InfoPage.pendingEpisode = null;
    if (!mounted) return;
    KazumiDialog.showToast(message: '来自分享链接，请选择第 $ep 集');
    showAdaptiveBottomSheet<void>(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      context: context,
      builder: (context) {
        return SourceSheet(infoController: infoController);
      },
    );
  }

  void onInfoTabChanged() {
    final index = infoTabController.index;
    if (index == 2 &&
        infoController.characterList.isEmpty &&
        !charactersIsLoading &&
        !charactersIsEmpty &&
        !charactersQueryTimeout) {
      loadCharacters();
    }
    if (index == 4 &&
        infoController.staffList.isEmpty &&
        !staffIsLoading &&
        !staffIsEmpty &&
        !staffQueryTimeout) {
      loadStaff();
    }
  }

  void _syncFabTabIndex() {
    final animation = infoTabController.animation;
    final targetIndex = infoTabController.indexIsChanging
        ? infoTabController.index
        : (animation?.value.round() ?? infoTabController.index);
    final nextIndex =
        targetIndex.clamp(0, infoTabController.length - 1).toInt();

    if (_fabTabIndex == nextIndex) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _fabTabIndex = nextIndex;
    });
  }

  Future<void> onCommentsTabSelected() async {
    final interest = infoController.bangumiItem.interest;
    final token =
        GStorage.getSetting(SettingsKeys.bangumiAccessToken).toString().trim();
    if (interest != null && token.isNotEmpty) {
      final updated = await infoController.fillInterestUserProfileIfNeeded();
      if (updated && mounted) {
        setState(() {});
      }
    }
    if (infoController.commentsList.isEmpty &&
        !commentsIsLoading &&
        !commentsIsEmpty &&
        !commentsQueryTimeout) {
      loadMoreComments();
    }
  }

  @override
  void dispose() {
    infoTabController.removeListener(onInfoTabChanged);
    infoTabController.removeListener(_syncFabTabIndex);
    infoTabController.animation?.removeListener(_syncFabTabIndex);
    infoController.characterList.clear();
    infoController.clearComments();
    infoController.staffList.clear();
    infoController.pluginSearchResponseList.clear();
    sourceTabController.dispose();
    infoTabController.dispose();
    super.dispose();
  }

  Future<void> queryBangumiInfoByID(
    int id, {
    String type = "init",
    bool enforceMinimumLoadingDuration = false,
  }) async {
    final loadingStartedAt = DateTime.now();
    try {
      await infoController.queryBangumiInfoByID(id, type: type);
    } catch (e) {
      KazumiLogger()
          .e('InfoPage: failed to query bangumi info by ID', error: e);
    } finally {
      if (enforceMinimumLoadingDuration && mounted) {
        await _waitForMinimumBangumiInfoLoadingDuration(loadingStartedAt);
      }
      if (mounted) {
        setState(() {
          _showBangumiInfoSkeleton = false;
        });
      }
    }
  }

  Future<void> _waitForMinimumBangumiInfoLoadingDuration(
      DateTime loadingStartedAt) async {
    final elapsed = DateTime.now().difference(loadingStartedAt);
    final remaining = _minimumBangumiInfoLoadingDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
  }

  /// 添加到播放列表
  void _addToPlaylist(BuildContext context) async {
    final bangumi = infoController.bangumiItem;
    final service = PlaylistService();
    final playlists = await service.getPlaylists();
    
    if (playlists.isEmpty) {
      final name = bangumi.nameCn.isNotEmpty ? bangumi.nameCn : bangumi.name;
      await service.createPlaylist(name);
      KazumiDialog.showToast(message: '已创建播放列表「$name」');
      return;
    }

    // 弹出选择列表
    final selected = await showAdaptiveBottomSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('选择播放列表', style: Theme.of(ctx).textTheme.titleMedium),
          ),
          ...playlists.map((p) => ListTile(
            title: Text(p.name),
            trailing: const Icon(Icons.add_rounded),
            onTap: () => Navigator.pop(ctx, p.id),
          )),
        ],
      ),
    );

    if (selected != null) {
      final name = bangumi.nameCn.isNotEmpty ? bangumi.nameCn : bangumi.name;
      await service.addToPlaylist(selected, PlaylistItem(
        bangumiItem: bangumi,
        adapterName: '',
        episodeNumber: 0,
        episodeTitle: name,
        src: '',
        road: 0,
        addedTime: DateTime.now(),
      ));
      KazumiDialog.showToast(message: '已添加到播放列表');
    }
  }

  /// 分享番剧：弹出分享面板（复制文案 / 复制深链 / 打开 Bangumi 页）
  void _showShareSheet(BuildContext context) {
    final item = infoController.bangumiItem;
    final name = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    final shareText = _buildShareText(item, name);
    // 分享只复制 ID（纯数字），打开 App 后通过剪贴板检测自动打开详情
    final lastEp = _lastWatchEpisodeFor(item);
    // ⭐ 分享链接带集数：好友点开直达下一集（ep = 上次看到 + 1）
    final deepLink = lastEp > 0
        ? 'https://qlyyz.xyz/yhdm/detail.html?id=${item.id}&ep=${lastEp + 1}'
        : 'https://qlyyz.xyz/yhdm/detail.html?id=${item.id}';

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.share_rounded, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '分享番剧',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 番剧卡片预览（走镜像加载）
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: NetworkImgLayer(
                        src: item.images['large'] ?? '',
                        width: 56,
                        height: 78,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.ratingScore > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '评分 ${item.ratingScore.toStringAsFixed(1)}',
                              style: TextStyle(color: colorScheme.primary),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            item.summary.isEmpty
                                ? '暂无简介'
                                : item.summary.replaceAll('\n', ' '),
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 分享文案预览
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    shareText,
                    style: Theme.of(ctx).textTheme.bodySmall,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shareText));
                          Navigator.pop(ctx);
                          KazumiDialog.showToast(message: '已复制分享文案');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('复制文案'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: deepLink));
                          Navigator.pop(ctx);
                          KazumiDialog.showToast(message: '已复制番剧ID，打开 App 自动打开');
                        },
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('网页版观看'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          launchUrl(
                            Uri.parse('https://bangumi.tv/subject/${item.id}'),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                        label: const Text('Bangumi'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ⭐ 生成二维码（内容为深链，不带集数，扫码直达详情页）
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showShareQrcode(context, item, name),
                    icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                    label: const Text('生成二维码'),                  ),
                ),
                const SizedBox(height: 4),
                // 🆕 分享给好友（发 anime 消息到好友聊天）
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await FriendPicker.shareAnime(
                        context,
                        name: name,
                        link: deepLink,
                      );
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('分享给好友'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 生成分享二维码弹窗（内容为深链，不带集数）
  void _showShareQrcode(BuildContext context, BangumiItem item, String name) {
    // 二维码内容：直接打开详情页（去除 ep 级数）
    final deepLink = 'yhdmgz://share/anime?id=${item.id}';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('扫码打开「$name」'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: QrImageView(
                data: deepLink,
                version: QrVersions.auto,
                size: 200,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              deepLink,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '用另一台设备的相机/扫码功能扫描，打开 App 直达详情页',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: deepLink));
              Navigator.pop(ctx);
              KazumiDialog.showToast(message: '已复制深链');
            },
            child: const Text('复制链接'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  /// 生成分享文案
  String _buildShareText(BangumiItem item, String name) {
    final sb = StringBuffer();
    sb.writeln('【$name】');
    if (item.ratingScore > 0) {
      sb.writeln('评分：${item.ratingScore.toStringAsFixed(1)}');
    }
    // ⭐ 带上观看进度（上次看到第几集）
    final lastEp = _lastWatchEpisodeFor(item);
    if (lastEp > 0) {
      sb.writeln('看到第 $lastEp 集');
    }
    if (item.summary.isNotEmpty) {
      final summary = item.summary.replaceAll('\n', ' ').trim();
      sb.writeln(
        summary.length > 80 ? '${summary.substring(0, 80)}...' : summary,
      );
    }
    sb.writeln('https://bangumi.tv/subject/${item.id}');
    return sb.toString();
  }

  /// 该番上次看到的集数（来自历史记录）
  int _lastWatchEpisodeFor(BangumiItem item) {
    try {
      for (final h in HistoryRepository().getAllHistories()) {
        if (h.bangumiItem.id == item.id) return h.lastWatchEpisode;
      }
    } catch (_) {}
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ 未成年人保护：详情页检测到 18+ 内容直接屏蔽（不显示封面/简介/选集）
    if (NsfwFilter.isNsfw(infoController.bangumiItem)) {
      return Scaffold(
        appBar: SysAppBar(title: const Text('内容已屏蔽')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shield,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                const Text(
                  '该番剧包含 18+ 内容',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '为保护青少年，此类内容已被隐藏。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final bool showWindowButton =
        GStorage.getSetting(SettingsKeys.showWindowButton);
    final bool showRatingFab = _fabTabIndex == _commentsTabIndex;
    return PopScope(
      canPop: true,
      child: DefaultTabController(
        length: _infoTabs.length,
        child: Scaffold(
          body: NestedScrollView(
            headerSliverBuilder:
                (BuildContext context, bool innerBoxIsScrolled) {
              return <Widget>[
                SliverOverlapAbsorber(
                  handle:
                      NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                  sliver: SliverAppBar.medium(
                    title: EmbeddedNativeControlArea(
                      child: dtb.DragToMoveArea(
                        child: Container(
                          width: double.infinity,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            infoController.bangumiItem.nameCn == ''
                                ? infoController.bangumiItem.name
                                : infoController.bangumiItem.nameCn,
                          ),
                        ),
                      ),
                    ),
                    automaticallyImplyLeading: false,
                    scrolledUnderElevation: 0.0,
                    leading: EmbeddedNativeControlArea(
                      child: IconButton(
                        onPressed: () {
                          context.maybePop();
                        },
                        icon: Icon(Icons.arrow_back),
                      ),
                    ),
                    actions: [
                      if (innerBoxIsScrolled)
                        EmbeddedNativeControlArea(
                          child: CollectButton(
                            bangumiItem: infoController.bangumiItem,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      // 添加到播放列表
                      EmbeddedNativeControlArea(
                        child: IconButton(
                          onPressed: () => _addToPlaylist(context),
                          icon: const Icon(Icons.playlist_add_rounded),
                          tooltip: '添加到播放列表',
                        ),
                      ),
                      // 分享番剧
                      EmbeddedNativeControlArea(
                        child: IconButton(
                          onPressed: () => _showShareSheet(context),
                          icon: const Icon(Icons.share_rounded),
                          tooltip: '分享',
                        ),
                      ),
                      EmbeddedNativeControlArea(
                        child: IconButton(
                          onPressed: () {
                            launchUrl(
                              Uri.parse(
                                  'https://bangumi.tv/subject/${infoController.bangumiItem.id}'),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.open_in_browser_rounded),
                        ),
                      ),

                      if (!showWindowButton && isDesktop())
                        CloseButton(onPressed: () => windowManager.close()),
                      SizedBox(width: 8),
                    ],
                    toolbarHeight: (Platform.isMacOS && showWindowButton)
                        ? kToolbarHeight + 22
                        : kToolbarHeight,
                    stretch: true,
                    centerTitle: false,
                    expandedHeight: (Platform.isMacOS && showWindowButton)
                        ? 308 + kTextTabBarHeight + kToolbarHeight + 22
                        : 308 + kTextTabBarHeight + kToolbarHeight,
                    collapsedHeight: (Platform.isMacOS && showWindowButton)
                        ? kTextTabBarHeight +
                            kToolbarHeight +
                            MediaQuery.paddingOf(context).top +
                            22
                        : kTextTabBarHeight +
                            kToolbarHeight +
                            MediaQuery.paddingOf(context).top,
                    flexibleSpace: FlexibleSpaceBar(
                      collapseMode: CollapseMode.pin,
                      background: Observer(builder: (context) {
                        final showBangumiInfoSkeleton =
                            _isShowingBangumiInfoSkeleton;
                        return Stack(
                          children: [
                            // No background image when loading to make loading looks better
                            if (!showBangumiInfoSkeleton)
                              Positioned.fill(
                                bottom: kTextTabBarHeight,
                                child: IgnorePointer(
                                  child: _InfoHeaderBackground(
                                    imageUrl: infoController
                                            .bangumiItem.images['large'] ??
                                        '',
                                  ),
                                ),
                              ),
                            SafeArea(
                              bottom: false,
                              child: EmbeddedNativeControlArea(
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, kToolbarHeight, 16, 0),
                                    child: BangumiInfoCardV(
                                      bangumiItem: infoController.bangumiItem,
                                      isLoading: showBangumiInfoSkeleton,
                                      showRating: showRating,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                    forceElevated: innerBoxIsScrolled,
                    bottom: TabBar(
                      controller: infoTabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.center,
                      dividerHeight: 0,
                      tabs: _infoTabs.map((name) => Tab(text: name)).toList(),
                    ),
                  ),
                ),
              ];
            },
            body: Observer(builder: (context) {
              final showBangumiInfoSkeleton = _isShowingBangumiInfoSkeleton;
              return InfoTabView(
                tabController: infoTabController,
                bangumiItem: infoController.bangumiItem,
                commentsQueryTimeout: commentsQueryTimeout,
                commentsIsEmpty: commentsIsEmpty,
                charactersQueryTimeout: charactersQueryTimeout,
                charactersIsEmpty: charactersIsEmpty,
                staffQueryTimeout: staffQueryTimeout,
                staffIsEmpty: staffIsEmpty,
                loadMoreComments: loadMoreComments,
                loadCharacters: loadCharacters,
                loadStaff: loadStaff,
                commentsList: infoController.commentsList,
                commentsIsLoading: commentsIsLoading,
                onCommentsTabSelected: onCommentsTabSelected,
                onPublishComment: (text, rating) =>
                    infoController.addCustomComment(text, rating: rating),
                onRefreshComments: () =>
                    infoController.queryBangumiCommentsByID(
                        infoController.bangumiItem.id),
                characterList: infoController.characterList,
                staffList: infoController.staffList,
                isLoading: showBangumiInfoSkeleton,
              );
            }),
          ),
          floatingActionButton: showRatingFab
              ? FloatingActionButton.extended(
                  tooltip: '吐槽',
                  onPressed: onBangumiRatingTap,
                  label: const Text('发表吐槽'),
                  icon: const Icon(Icons.rate_review_rounded),
                )
              : FloatingActionButton.extended(
                  tooltip: '开始观看',
                  onPressed: () {
                    showAdaptiveBottomSheet<void>(
                      backgroundColor:
                          Theme.of(context).scaffoldBackgroundColor,
                      context: context,
                      builder: (context) {
                        return SourceSheet(
                            infoController: infoController);
                      },
                    );
                  },
                  label: const Text('开始观看'),
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
        ),
      ),
    );
  }
}

class _InfoHeaderBackground extends StatelessWidget {
  const _InfoHeaderBackground({
    required this.imageUrl,
  });

  static const double _downsample = 0.5;
  static const double _blurSigma = 15.0;
  static const double _opacity = 0.4;
  static const double _edgeBleed = 32.0;
  static const double _bottomFeatherHeight = 48.0;

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        final rasterWidth = width * _downsample;
        final rasterHeight = (height + _edgeBleed) * _downsample;

        final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShaderMask(
                shaderCallback: (bounds) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0.8, 1],
                  ).createShader(bounds);
                },
                child: Align(
                  alignment: Alignment.topCenter,
                  child: RepaintBoundary(
                    child: Transform.scale(
                      scale: 1 / _downsample,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.low,
                      child: SizedBox(
                        width: rasterWidth,
                        height: rasterHeight,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: _blurSigma * _downsample,
                            sigmaY: _blurSigma * _downsample,
                          ),
                          child: NetworkImgLayer(
                            src: imageUrl,
                            width: rasterWidth,
                            height: rasterHeight,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            filterQuality: FilterQuality.low,
                            color: Colors.white.withValues(alpha: _opacity),
                            colorBlendMode: BlendMode.modulate,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _bottomFeatherHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        backgroundColor.withValues(alpha: 0),
                        backgroundColor.withValues(alpha: 0.55),
                        backgroundColor,
                      ],
                      stops: const [0, 0.72, 1],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

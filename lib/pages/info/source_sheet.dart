import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/playlist/play_queue_service.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/widgets/comment/comment_list.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'dart:async';
import 'dart:convert';
import 'package:kazumi/services/plugin/captcha_verification_service.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/utils/device.dart';

class SourceSheet extends StatefulWidget {
  const SourceSheet({
    super.key,
    required this.infoController,
  });

  final InfoController infoController;

  @override
  State<SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<SourceSheet>
    with SingleTickerProviderStateMixin {
  final CollectController collectController = inject<CollectController>();
  final PluginsController pluginsController = inject<PluginsController>();
  late String keyword;
  late TabController _sourceTabController;

  /// Concurrent plugin search service.
  PluginSearchService? pluginSearchService;

  /// Captcha verification service (created on demand)
  CaptchaVerificationService? _captchaVerificationService;

  /// 排序后的插件列表：绿→蓝→黄→红，同色按名排序
  /// 已禁用的规则不显示，合集展开为子规则
  /// 只显示有搜索 URL 的规则（合集本身不搜索），支持关键词过滤
  List<Plugin> get _filteredPlugins {
    final expanded = <Plugin>[];
    for (final p in pluginsController.pluginList) {
      if (!p.enabled) continue;
      if (p.isCollection && p.childPlugins.isNotEmpty) {
        for (final child in p.childPlugins) {
          if (child.enabled && child.searchURL.isNotEmpty) {
            expanded.add(child);
          }
        }
      } else if (!p.isCollection) {
        expanded.add(p);
      }
    }
    final sorted = List<Plugin>.from(expanded)
      ..sort((a, b) {
        // 🆕 星标规则无条件排最前
        final starA = _starred.contains(a.name) ? 0 : 1;
        final starB = _starred.contains(b.name) ? 0 : 1;
        if (starA != starB) return starA.compareTo(starB);
        final sa = widget.infoController.pluginSearchStatus[a.name];
        final sb = widget.infoController.pluginSearchStatus[b.name];
        const order = {
          PluginSearchStatus.success: 0,
          PluginSearchStatus.captcha: 1,
          PluginSearchStatus.noResult: 2,
          PluginSearchStatus.error: 3,
        };
        final oa = order[sa] ?? 4;
        final ob = order[sb] ?? 4;
        if (oa != ob) return oa.compareTo(ob);
        return a.name.compareTo(b.name);
      });
    // 关键词过滤
    if (_filterText.isNotEmpty) {
      return sorted.where((p) =>
        p.name.toLowerCase().contains(_filterText)
      ).toList();
    }
    return sorted;
  }

  /// Timeout timer waiting for captcha verification result
  Timer? _captchaVerifyTimer;

  /// 搜索源过滤
  final TextEditingController _filterController = TextEditingController();
  String _filterText = '';

  /// ⭐ 自动选源：已自动选中标志 + 轮询定时器
  bool _autoSelected = false;
  Timer? _autoSelectTimer;

  /// ⭐ 当前Tab索引（用于浏览器打开）
  int _currentTabIndex = 0;

  /// 🆕 星标规则名（播放时无条件排最前）
  final Set<String> _starred = {};

  @override
  void initState() {
    super.initState();
    keyword = widget.infoController.bangumiItem.nameCn == ''
        ? widget.infoController.bangumiItem.name
        : widget.infoController.bangumiItem.nameCn;
    // TabController 长度 = 插件数 + 1（评论 Tab）
    _sourceTabController = TabController(
      length: _filteredPlugins.length + 1,
      vsync: this,
    );
    // ⭐ 监听 Tab 变化，更新当前索引
    _sourceTabController.addListener(() {
      if (_sourceTabController.indexIsChanging || _sourceTabController.index != _currentTabIndex) {
        _currentTabIndex = _sourceTabController.index;
      }
    });
    pluginSearchService = PluginSearchService(
      infoController: widget.infoController,
      pluginsController: pluginsController,
    );
    pluginSearchService?.queryAllSource(keyword);
    // 🆕 加载星标规则（用于源排序优先）
    SocialService.getStarRules().then((stars) {
      if (!mounted) return;
      setState(() => _starred.addAll(stars));
    });
    // ⭐ 自动选源：设置开启时，自动选第一个可用的源播放
    if (GStorage.getSetting(SettingsKeys.autoSelectSource)) {
      // ⭐ 优化：减少轮询间隔到 100ms，提升速度
      _autoSelectTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _maybeAutoSelectSource();
      });
    }
  }

  /// 🆕 自动选源等待开始时间（超过上限仍未找到则提示手动选择）
  DateTime? _autoSelectStartedAt;

  /// ⭐ 自动选第一个可用的源（只触发一次）；应用星标优先 + 排序模式
  void _maybeAutoSelectSource() {
    if (_autoSelected || !mounted) return;
    _autoSelectStartedAt ??= DateTime.now();
    // 🔧 等待上限：5 秒内无可用源 → 提示手动选择，停止空等
    if (DateTime.now().difference(_autoSelectStartedAt!).inSeconds >= 5) {
      _autoSelectTimer?.cancel();
      _autoSelectTimer = null;
      KazumiDialog.showToast(message: '自动选源超时，请手动选择线路');
      return;
    }
    // 🔧 按星标 + 排序模式（清晰度/集数/速度）重排响应，再取第一个可用源
    final responses = List.of(widget.infoController.pluginSearchResponseList)
      ..sort((a, b) {
        final sa = _starred.contains(a.pluginName) ? 0 : 1;
        final sb = _starred.contains(b.pluginName) ? 0 : 1;
        if (sa != sb) return sa.compareTo(sb);
        return _scoreSource(b).compareTo(_scoreSource(a));
      });
    for (final resp in responses) {
      if (resp.data.isEmpty) continue;
      Plugin? matched;
      for (final p in pluginsController.pluginList) {
        if (p.name == resp.pluginName) {
          matched = p;
          break;
        }
      }
      if (matched == null) continue;
      _autoSelected = true;
      _autoSelectTimer?.cancel();
      _playWithSource(matched, resp.data.first);
      return;
    }
  }

  /// 🆕 按规则设置的排序模式给响应打分（越高越优先）
  int _scoreSource(dynamic resp) {
    var score = 0;
    final useDefault =
        GStorage.getSetting(SettingsKeys.ruleSortDefault);
    final byQuality =
        GStorage.getSetting(SettingsKeys.ruleSortQuality);
    final byEpisodes =
        GStorage.getSetting(SettingsKeys.ruleSortEpisodes);
    final bySpeed = GStorage.getSetting(SettingsKeys.ruleSortSpeed);
    if (useDefault && !byQuality && !byEpisodes && !bySpeed) {
      // 全默认：所有源同分（按返回顺序）
      return 0;
    }
    final data = (resp.data is List) ? resp.data as List : const [];
    // 集数最多：搜索结果命中条数多为优（集数线索）
    if (byEpisodes) {
      score += data.length * 10;
    }
    // 清晰度最高：名称/地址含高清关键词优先（启发式）
    if (byQuality) {
      final text = data.map((s) {
        try {
          final name = (s as dynamic).name?.toString() ?? '';
          final src = (s as dynamic).src?.toString() ?? '';
          return '$name $src';
        } catch (_) {
          return '';
        }
      }).join(' ').toLowerCase();
      if (RegExp(r'1080|2160|4k|hd|高清|超清|bluray|web-dl').hasMatch(text)) {
        score += 100;
      }
    }
    // 速度最快：默认同分（不测速，保持响应顺序）
    if (bySpeed) {
      score += 1;
    }
    return score;
  }

  /// 🔧 验证成功后：只自动播放"刚验证成功"的那条规则的结果，不切到其他源
  void _autoPlayVerifiedPlugin(String pluginName) {
    if (_autoSelected || !mounted) return;
    Plugin? matched;
    for (final p in pluginsController.pluginList) {
      if (p.name == pluginName) {
        matched = p;
        break;
      }
    }
    if (matched == null) return;
    for (final resp in widget.infoController.pluginSearchResponseList) {
      if (resp.pluginName == pluginName && resp.data.isNotEmpty) {
        _autoSelected = true;
        _autoSelectTimer?.cancel();
        _playWithSource(matched, resp.data.first);
        return;
      }
    }
  }

  @override
  void dispose() {
    _autoSelectTimer?.cancel();
    _autoSelectTimer = null;
    _sourceTabController.dispose();
    pluginSearchService?.cancel();
    pluginSearchService = null;
    _captchaVerificationService?.dispose();
    _captchaVerificationService = null;
    _captchaVerifyTimer?.cancel();
    _captchaVerifyTimer = null;
    super.dispose();
  }

  /// 🆕 长按搜索结果 → 加入连播队列（播放完自动接播下一项，无需重新搜索）
  Future<void> _addResultToQueue(Plugin plugin, SearchItem searchItem) async {
    try {
      KazumiDialog.showLoading(msg: '解析分集中...');
      final roads = await plugin.queryChapterRoads(searchItem.src);
      KazumiDialog.dismiss();
      if (!mounted) return;
      if (roads.isEmpty) {
        KazumiDialog.showToast(message: '该结果解析分集失败');
        return;
      }
      final item = PlayQueueItem(
        bangumiItem: widget.infoController.bangumiItem,
        plugin: plugin,
        title: searchItem.name,
        src: searchItem.src,
        roads: roads,
        episode: 1,
        road: 0,
        addedTime: DateTime.now(),
      );
      final added = await PlayQueueService.instance.add(item);
      if (!mounted) return;
      KazumiDialog.showToast(
          message: added
              ? '✅ 已加入连播队列（当前队列 ${PlayQueueService.instance.length} 项）'
              : '该结果已在队列中');
    } catch (e) {
      KazumiDialog.dismiss();
      KazumiLogger().w('AddToQueue: 失败', error: e);
      if (mounted) KazumiDialog.showToast(message: '加入队列失败：$e');
    }
  }

  /// ⭐ 用指定源+结果抓取分集并进入播放器（手动点击和自动选源共用）
  Future<void> _playWithSource(Plugin plugin, SearchItem searchItem) async {
    if (!mounted) return;
    final cancelToken = RuleCancelToken();
    KazumiDialog.showLoading(
      msg: '获取中',
      barrierDismissible: isDesktop(),
      onDismiss: cancelToken.cancel,
    );
    try {
      final roads = await plugin.queryChapterRoads(
        searchItem.src,
        cancelToken: cancelToken,
      );
      if (roads.isEmpty) {
        throw ChapterErrorException(plugin.name);
      }
      KazumiDialog.dismiss();
      if (!mounted) return;
      this.context.pushNamed(
            '/video/',
            arguments: OnlineVideoPlaybackArgs(
              bangumiItem: widget.infoController.bangumiItem,
              plugin: plugin,
              title: searchItem.name,
              src: searchItem.src,
              roads: roads,
            ),
          );
    } catch (_) {
      KazumiLogger().w(
          "PluginSearchService: failed to query video playlist");
      KazumiDialog.dismiss();
      // ⭐ 自动选源失败：允许继续尝试下一个源
      if (_autoSelected) {
        _autoSelected = false;
        if (mounted && GStorage.getSetting(SettingsKeys.autoSelectSource)) {
          _autoSelectTimer = Timer.periodic(
              const Duration(milliseconds: 100), (_) {
            _maybeAutoSelectSource();
          });
        }
      }
    }
  }

  /// ⭐ 在浏览器中打开当前选中的源
  void _openInBrowser() {
    final currentIndex = _currentTabIndex;
    
    if (currentIndex < 0 || currentIndex >= _filteredPlugins.length) {
      KazumiDialog.showToast(message: '请先选择一个播放源');
      return;
    }
    
    final currentPlugin = _filteredPlugins[currentIndex];
    if (currentPlugin == null) {
      KazumiDialog.showToast(message: '未找到对应的播放源');
      return;
    }
    
    // 🆕 统一用 searchURL 拼接关键词打开（不再区分 API 模式）
    final targetUrl = currentPlugin.searchURL.replaceFirst(
      '@keyword',
      Uri.encodeQueryComponent(keyword),
    );
    
    launchUrl(
      Uri.parse(targetUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  void showAntiCrawlerDialog(Plugin plugin) {
    switch (plugin.antiCrawlerConfig.captchaType) {
      case CaptchaType.customJavaScript:
        showCustomScriptDialog(plugin);
        break;
      case CaptchaType.autoClickButton:
        showButtonClickDialog(plugin);
        break;
      default:
        showCaptchaDialog(plugin);
    }
  }

  void showCaptchaDialog(Plugin plugin) {
    /// flag whether verification has passed, used to distinguish normal dismissal from cancellation in onDismiss
    bool verified = false;

    _captchaVerificationService?.dispose();
    _captchaVerificationService = CaptchaVerificationService();

    final searchUrl = plugin.searchURL
        .replaceAll('@keyword', Uri.encodeQueryComponent(keyword));

    _captchaVerificationService!.loadForCaptcha(
      searchUrl,
      plugin.antiCrawlerConfig.captchaImage,
      inputXpath: plugin.antiCrawlerConfig.captchaInput,
    );

    Future<void> submitCaptcha(String captchaCode) async {
      await _captchaVerificationService?.submitCaptcha(
        captchaCode: captchaCode.trim(),
        inputXpath: plugin.antiCrawlerConfig.captchaInput,
        buttonXpath: plugin.antiCrawlerConfig.captchaButton,
        pluginName: plugin.name,
        onVerified: () {
          _captchaVerifyTimer?.cancel();
          _captchaVerifyTimer = null;
          verified = true;
          // 🔧 关闭可能的加载框，避免"进度条过了还在加载中"
          KazumiDialog.dismiss();
          // 🔧 锁定：验证成功后停掉自动选源，绝不切到其他规则
          _autoSelectTimer?.cancel();
          _autoSelectTimer = null;
          // 🔧 恢复"验证成功"进度条提示（用户喜欢这个规则，锁定到它）
          KazumiDialog.showTimedSuccessDialog(
            title: '验证成功',
            message: '已锁定当前规则，正在重新检索…',
            onComplete: () {
              pluginSearchService?.querySource(keyword, plugin.name).then((_) {
                _autoPlayVerifiedPlugin(plugin.name);
              });
            },
          );
        },
      );
      // submitCaptcha completes after the JS button click is fired.
      // Start the 8-second timeout only NOW, waiting for the webview to
      // detect the captcha disappearing and call onVerified.
      if (!verified) {
        _captchaVerifyTimer?.cancel();
        _captchaVerifyTimer = Timer(const Duration(seconds: 8), () {
          if (!verified) {
            KazumiDialog.dismiss();
          }
        });
      }
    }

    KazumiDialog.show(
      onDismiss: () async {
        _captchaVerifyTimer?.cancel();
        _captchaVerifyTimer = null;
        // Capture the current service instance locally before any await.
        // Without this, an async gap could allow _captchaVerificationService to be
        // replaced (or nulled by _SourceSheetState.dispose()), causing the
        // closure to dispose the wrong/already-disposed instance.
        final captchaService = _captchaVerificationService;
        _captchaVerificationService = null;
        if (!verified) {
          await captchaService?.saveAndUnload(plugin.name);
          captchaService?.dispose();
          pluginSearchService?.querySource(keyword, plugin.name);
        } else {
          captchaService?.dispose();
        }
      },
      builder: (context) => _CaptchaDialog(
        pluginName: plugin.name,
        captchaImageStream: _captchaVerificationService!.onCaptchaImageUrl,
        onSubmit: submitCaptcha,
      ),
    );
  }

  void showButtonClickDialog(Plugin plugin) {
    showAutomatedVerifyDialog(
      plugin,
      statusText: '${plugin.name} 正在自动完成验证，请稍候',
      detailText: '已检测到验证按钮并模拟点击，等待验证通过…',
      startVerification: (captchaService, searchUrl, onVerified) {
        return captchaService.loadForButtonClick(
          url: searchUrl,
          buttonXpath: plugin.antiCrawlerConfig.captchaButton,
          pluginName: plugin.name,
          onVerified: onVerified,
        );
      },
    );
  }

  void showCustomScriptDialog(Plugin plugin) {
    showAutomatedVerifyDialog(
      plugin,
      statusText: '${plugin.name} 正在执行验证脚本，请稍候',
      detailText: '已加载验证页面并执行自定义脚本，等待验证通过…',
      startVerification: (captchaService, searchUrl, onVerified) {
        return captchaService.loadForCustomScript(
          url: searchUrl,
          script: plugin.antiCrawlerConfig.captchaScript,
          pluginName: plugin.name,
          onVerified: onVerified,
        );
      },
    );
  }

  void showAutomatedVerifyDialog(
    Plugin plugin, {
    required String statusText,
    required String detailText,
    required Future<void> Function(
      CaptchaVerificationService captchaService,
      String searchUrl,
      void Function() onVerified,
    ) startVerification,
  }) {
    bool verified = false;

    _captchaVerificationService?.dispose();
    _captchaVerificationService = CaptchaVerificationService();

    final captchaService = _captchaVerificationService!;
    final searchUrl = plugin.searchURL
        .replaceAll('@keyword', Uri.encodeQueryComponent(keyword));

    void onVerified() {
      if (verified) return;
      verified = true;
      // 🔧 关闭可能的加载框，避免"进度条过了还在加载中"
      KazumiDialog.dismiss();
      // 🔧 锁定：验证成功后停掉自动选源，绝不切到其他规则
      _autoSelectTimer?.cancel();
      _autoSelectTimer = null;
      // 🔧 恢复"验证成功"进度条提示（锁定到当前规则）
      KazumiDialog.showTimedSuccessDialog(
        title: '验证成功',
        message: '已锁定当前规则，正在重新检索…',
        onComplete: () {
          pluginSearchService?.querySource(keyword, plugin.name).then((_) {
            _autoPlayVerifiedPlugin(plugin.name);
          });
        },
      );
    }

    unawaited(startVerification(captchaService, searchUrl, onVerified));

    KazumiDialog.show(
      onDismiss: () async {
        final captchaService = _captchaVerificationService;
        _captchaVerificationService = null;
        if (verified) {
          captchaService?.dispose();
        } else {
          await captchaService?.saveAndUnload(plugin.name);
          captchaService?.dispose();
          pluginSearchService?.querySource(keyword, plugin.name);
        }
      },
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '自动验证中',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  detailText,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => KazumiDialog.dismiss(),
                    child: Text(
                      '取消',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildPluginView(Plugin plugin, List<Widget> cardList) {
    final status = widget.infoController.pluginSearchStatus[plugin.name];
    if (status == PluginSearchStatus.pending) {
      return const Center(child: CircularProgressIndicator());
    }
    if (status == PluginSearchStatus.captcha) {
      return GeneralErrorWidget(
        errMsg: '${plugin.name} 需要验证码验证',
        actions: [
          GeneralErrorButton(
            onPressed: () => showAntiCrawlerDialog(plugin),
            text: '进行验证',
          ),
          GeneralErrorButton(
            onPressed: () =>
                pluginSearchService?.querySource(keyword, plugin.name),
            text: '重试',
          ),
        ],
      );
    }
    if (status == PluginSearchStatus.noResult) {
      return GeneralErrorWidget(
        errMsg: '${plugin.name} 无结果 使用别名或左右滑动以切换到其他视频来源',
        actions: [
          GeneralErrorButton(
            onPressed: () => showAliasSearchDialog(plugin.name),
            text: '别名检索',
          ),
          GeneralErrorButton(
            onPressed: () => showCustomSearchDialog(plugin.name),
            text: '手动检索',
          ),
        ],
      );
    }
    if (status == PluginSearchStatus.error) {
      return GeneralErrorWidget(
        errMsg: '${plugin.name} 检索失败 重试或左右滑动以切换到其他视频来源',
        actions: [
          GeneralErrorButton(
            onPressed: () =>
                pluginSearchService?.querySource(keyword, plugin.name),
            text: '重试',
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: cardList,
          ),
        ),
        if (cardList.isNotEmpty) showSupplementarySearchEntry(plugin.name),
      ],
    );
  }

  /// Fallback search entry under the result list, for when the default
  /// keyword produced inaccurate matches.
  Widget showSupplementarySearchEntry(String pluginName) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
                runSpacing: 4,
                children: [
                  Text(
                    '结果不准确？',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withValues(alpha: 0.75),
                        ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      textStyle: Theme.of(context).textTheme.bodySmall,
                    ),
                    onPressed: () => showAliasSearchDialog(pluginName),
                    child: const Text('别名检索'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      textStyle: Theme.of(context).textTheme.bodySmall,
                    ),
                    onPressed: () => showCustomSearchDialog(pluginName),
                    child: const Text('手动检索'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void showAliasSearchDialog(String pluginName) {
    if (widget.infoController.bangumiItem.alias.isEmpty) {
      KazumiDialog.showToast(message: '无可用别名，试试手动检索');
      return;
    }
    KazumiDialog.show(
      builder: (context) {
        return _AliasDialog(
          aliases: widget.infoController.bangumiItem.alias,
          onAliasSelected: (alias) {
            KazumiDialog.dismiss();
            pluginSearchService?.querySource(alias, pluginName);
          },
          onAliasesChanged: () {
            collectController
                .updateLocalCollect(widget.infoController.bangumiItem);
          },
        );
      },
    );
  }

  void showCustomSearchDialog(String pluginName) {
    String customKeyword = '';

    void submit(String value) {
      final alias = value.trim();
      if (alias.isEmpty) {
        return;
      }
      widget.infoController.bangumiItem.alias.add(alias);
      collectController.updateLocalCollect(widget.infoController.bangumiItem);
      KazumiDialog.dismiss();
      pluginSearchService?.querySource(alias, pluginName);
    }

    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          title: const Text('输入别名'),
          content: TextField(
            onChanged: (value) => customKeyword = value,
            onSubmitted: (keyword) {
              submit(keyword);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                KazumiDialog.dismiss();
              },
              child: Text(
                '取消',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                submit(customKeyword);
              },
              child: const Text(
                '确认',
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          MaterialBottomSheetHeader(
            title: '选择播放源',
            description: '正在检索“$keyword”',
            onClose: () => Navigator.of(context).pop(),
            footer: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                controller: _filterController,
                decoration: InputDecoration(
                  hintText: '🔍 输入关键词过滤源...',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _filterText.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _filterController.clear();
                            setState(() {
                              _filterText = '';
                              _sourceTabController = TabController(
                                length: _filteredPlugins.length + 1,
                                vsync: this,
                              );
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onChanged: (value) {
                  setState(() {
                    _filterText = value.trim().toLowerCase();
                    _sourceTabController = TabController(
                      length: _filteredPlugins.length + 1,
                      vsync: this,
                    );
                  });
                },
              ),
            ),
          ),
          Observer(
            builder: (context) => MaterialBottomSheetTabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              controller: _sourceTabController,
              tabs: _filteredPlugins
                  .map(
                    (plugin) => Tab(
                      child: Row(
                        children: [
                          Text(
                            plugin.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 5.0),
                          Container(
                            width: 8.0,
                            height: 8.0,
                            decoration: BoxDecoration(
                              color: switch (widget.infoController
                                  .pluginSearchStatus[plugin.name]) {
                                PluginSearchStatus.success => Colors.green,
                                PluginSearchStatus.noResult => Colors.orange,
                                PluginSearchStatus.captcha => Colors.blue,
                                PluginSearchStatus.error => Colors.red,
                                _ => Colors.grey,
                              },
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            // ⭐ 修复：浏览器打开按钮 - 使用修复后的方法
            trailing: IconButton(
              tooltip: '在浏览器中打开',
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_browser_rounded),
            ),
          ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Observer(
              builder: (context) => TabBarView(
                controller: _sourceTabController,
                children: List.generate(_filteredPlugins.length,
                    (pluginIndex) {
                  var plugin = _filteredPlugins[pluginIndex];
                  var cardList = <Widget>[];
                  for (var searchResponse
                      in widget.infoController.pluginSearchResponseList) {
                    if (searchResponse.pluginName == plugin.name) {
                      for (var searchItem in searchResponse.data) {
                        cardList.add(
                          Card(
                            elevation: 0,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                materialBottomSheetRadius,
                              ),
                            ),
                            margin: const EdgeInsets.only(
                                left: 10, right: 10, top: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                materialBottomSheetRadius,
                              ),
                              onTap: () {
                                _playWithSource(plugin, searchItem);
                              },
                              onLongPress: () {
                                _addResultToQueue(plugin, searchItem);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(searchItem.name),
                              ),
                            ),
                          ),
                        );
                      }
                    }
                  }
                  return buildPluginView(plugin, cardList);
                }),
                // 🆕 评论 Tab
                CommentListPage(
                  subjectId: widget.infoController.bangumiItem.id,
                  animeName: widget.infoController.bangumiItem.nameCn.isNotEmpty
                      ? widget.infoController.bangumiItem.nameCn
                      : widget.infoController.bangumiItem.name,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class _CaptchaDialog extends StatefulWidget {
  const _CaptchaDialog({
    required this.pluginName,
    required this.captchaImageStream,
    required this.onSubmit,
  });

  final String pluginName;
  final Stream<String?> captchaImageStream;
  final Future<void> Function(String captchaCode) onSubmit;

  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  final ValueNotifier<String?> _captchaImageNotifier =
      ValueNotifier<String?>(null);
  final ValueNotifier<bool> _submittingNotifier = ValueNotifier<bool>(false);
  late final StreamSubscription<String?> _imageSub;
  String _captchaCode = '';

  @override
  void initState() {
    super.initState();
    _imageSub = widget.captchaImageStream.listen((url) {
      if (!mounted || url == null) return;
      _captchaImageNotifier.value = url;
    });
  }

  @override
  void dispose() {
    _imageSub.cancel();
    _captchaImageNotifier.dispose();
    _submittingNotifier.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submittingNotifier.value) return;
    final captchaCode = _captchaCode.trim();
    if (captchaCode.isEmpty) {
      KazumiDialog.showToast(message: '请输入验证码');
      return;
    }
    _submittingNotifier.value = true;
    await widget.onSubmit(captchaCode);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '验证码验证',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.pluginName} 需要验证码验证',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<String?>(
                valueListenable: _captchaImageNotifier,
                builder: (context, imageUrl, _) {
                  if (imageUrl == null) {
                    return const Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('正在加载验证码图片...'),
                      ],
                    );
                  }
                  return ValueListenableBuilder<bool>(
                    valueListenable: _submittingNotifier,
                    builder: (context, isSubmitting, _) {
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              base64Decode(imageUrl.split(',').last),
                              height: 80,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, _) =>
                                  const Text('图片解码失败'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            autofocus: true,
                            enabled: !isSubmitting,
                            onChanged: (value) => _captchaCode = value,
                            decoration: const InputDecoration(
                              labelText: '请输入验证码',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: isSubmitting ? null : (_) => _submit(),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              ListenableBuilder(
                listenable: Listenable.merge([
                  _captchaImageNotifier,
                  _submittingNotifier,
                ]),
                builder: (context, _) {
                  final isImageLoading = _captchaImageNotifier.value == null;
                  final isSubmitting = _submittingNotifier.value;
                  final isDisabled = isImageLoading || isSubmitting;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => KazumiDialog.dismiss(),
                        child: Text(
                          '取消',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: isDisabled ? null : _submit,
                        child: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('提交'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AliasDialog extends StatefulWidget {
  const _AliasDialog({
    required this.aliases,
    required this.onAliasSelected,
    required this.onAliasesChanged,
  });

  final List<String> aliases;
  final ValueChanged<String> onAliasSelected;
  final VoidCallback onAliasesChanged;

  @override
  State<_AliasDialog> createState() => _AliasDialogState();
}

class _AliasDialogState extends State<_AliasDialog> {
  late final ValueNotifier<List<String>> aliasNotifier =
      ValueNotifier<List<String>>(List.from(widget.aliases));

  @override
  void dispose() {
    aliasNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 560,
        child: ValueListenableBuilder<List<String>>(
          valueListenable: aliasNotifier,
          builder: (context, aliasList, child) {
            return ListView(
              shrinkWrap: true,
              children: aliasList.asMap().entries.map((entry) {
                final index = entry.key;
                final alias = entry.value;
                return ListTile(
                  title: Text(alias),
                  trailing: IconButton(
                    onPressed: () {
                      KazumiDialog.show(
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('删除确认'),
                            content: const Text('删除后无法恢复，确认要永久删除这个别名吗？'),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  KazumiDialog.dismiss();
                                },
                                child: Text(
                                  '取消',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  KazumiDialog.dismiss();
                                  widget.aliases.removeAt(index);
                                  aliasNotifier.value =
                                      List.from(widget.aliases);
                                  widget.onAliasesChanged();
                                  if (widget.aliases.isEmpty) {
                                    Navigator.of(this.context).pop();
                                  }
                                },
                                child: const Text('确认'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    icon: Icon(Icons.delete),
                  ),
                  onTap: () => widget.onAliasSelected(alias),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
import 'package:yhdm/bean/widget/loading_indicator.dart';
import 'dart:convert';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/storage/settings_keys.dart';
import 'package:yhdm/request/clients/download_http_client.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 活动通知服务（原公告升级）。
/// 接口路径不变: https://qlyyz.xyz/api/v0/notice?action=get
/// 新格式（参考 gong.xiaonanniang.cn/api/activities）:
///   {"code":0,"message":"ok","data":{"total":N,"page":1,"page_size":100,
///     "list":[{"id","title","summary","cover_image","images":[],"link_url",
///              "status","sort_order","start_time","end_time","view_count",
///              "created_at","updated_at"}]}}
/// 兼容旧格式: {"version":N,"list":[{title,content}]} 与单条 {version,title,content}
class AnnouncementService {
  static const String _apiUrl = 'https://qlyyz.xyz/api/v0/notice?action=get';

  static Future<void> checkAnnouncement() async {
    try {
      final client = DownloadHttpClient.instance;
      final response = await client.getPlain(_apiUrl);
      final data = json.decode(response) as Map<String, dynamic>;

      // 1) 新格式：code/data/list（分页活动）
      final newActivities = _parseNewActivities(data);
      if (newActivities.isNotEmpty) {
        final maxUpdated = _maxUpdatedAt(newActivities);
        final stored =
            GStorage.getSetting(SettingsKeys.activitiesUpdatedAt) ?? '';
        if (maxUpdated.isNotEmpty && maxUpdated.compareTo(stored) > 0) {
          _showActivityDialog(newActivities, maxUpdated);
        }
        return;
      }

      // 2) 旧格式：version + list / 单条
      final localVersion =
          GStorage.getSetting(SettingsKeys.announcementVersion) ?? 0;
      final version = data['version'] as int? ?? 0;
      final oldItems = <Map<String, String>>[];
      final rawList = data['list'];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is Map) {
            final t = (item['title'] ?? '').toString().trim();
            final c = (item['content'] ?? '').toString();
            if (c.isNotEmpty) {
              oldItems.add({'title': t.isEmpty ? '活动' : t, 'content': c});
            }
          }
        }
      } else {
        final t = (data['title'] ?? '活动').toString().trim();
        final c = (data['content'] ?? '').toString();
        if (c.isNotEmpty) {
          oldItems.add({'title': t.isEmpty ? '活动' : t, 'content': c});
        }
      }
      if (version > localVersion && oldItems.isNotEmpty) {
        _showOldActivityDialog(oldItems, version);
      }
    } catch (e) {
      KazumiLogger().w('Announcement: check failed', error: e);
    }
  }

  /// 解析新格式活动列表
  static List<ActivityItem> _parseNewActivities(Map<String, dynamic> data) {
    final rawData = data['data'];
    if (rawData is! Map) return [];
    final rawList = rawData['list'];
    if (rawList is! List) return [];
    final list = <ActivityItem>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final title = (item['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final images = <String>[];
      final rawImages = item['images'];
      if (rawImages is List) {
        for (final img in rawImages) {
          final s = img.toString().trim();
          if (s.isNotEmpty) images.add(s);
        }
      }
      list.add(ActivityItem(
        id: (item['id'] ?? '').toString(),
        title: title,
        summary: (item['summary'] ?? '').toString(),
        coverImage: (item['cover_image'] ?? '').toString(),
        images: images,
        linkUrl: (item['link_url'] ?? '').toString(),
        buttonText: (item['button_text'] ?? '').toString(),
        startTime: (item['start_time'] ?? '').toString(),
        endTime: (item['end_time'] ?? '').toString(),
        createdAt: (item['created_at'] ?? '').toString(),
        updatedAt: (item['updated_at'] ?? '').toString(),
      ));
    }
    return list;
  }

  /// 取最新 updated_at（作为版本锚点：新增/编辑后 App 重新弹出）
  static String _maxUpdatedAt(List<ActivityItem> items) {
    var max = '';
    for (final it in items) {
      if (it.updatedAt.isNotEmpty && it.updatedAt.compareTo(max) > 0) {
        max = it.updatedAt;
      }
    }
    return max;
  }

  static String _shortDate(String t) {
    return t.length >= 10 ? t.substring(0, 10) : t;
  }

  /// 判断内容是否为HTML（旧格式兼容）
  static bool _isHtml(String content) {
    final trimmed = content.trim();
    return trimmed.startsWith('<') &&
        (trimmed.contains('</') || trimmed.contains('/>'));
  }

  /// 活动列表弹窗（新格式）：封面 + 标题 + 摘要，默认展示最新 5 条可下滑；
  /// 点击条目弹出详情；点"我知道了"或勾选后仅记录当前版本锚点，新活动(updated_at 更新)仍会弹出。
  static void _showActivityDialog(List<ActivityItem> activities, String maxUpdated) {
    bool dontShowAgain = false;

    KazumiDialog.show(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final cs = Theme.of(context).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.celebration, color: cs.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('活动', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: activities.length,
                        itemBuilder: (context, index) {
                          final item = activities[index];
                          final date = _shortDate(
                              item.startTime.isNotEmpty ? item.startTime : item.createdAt);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: item.coverImage.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      item.coverImage,
                                      width: 48,
                                      height: 64,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => Container(
                                        width: 48,
                                        height: 64,
                                        color: cs.surfaceContainerHighest,
                                        alignment: Alignment.center,
                                        child: Icon(Icons.image_outlined,
                                            size: 20, color: cs.outline),
                                      ),
                                    ),
                                  )
                                : Icon(Icons.campaign_outlined,
                                    size: 24, color: cs.primary),
                            title: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              item.summary.isNotEmpty
                                  ? '$date · ${item.summary}'
                                  : date,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: cs.outline),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => _showActivityDetail(context, item),
                          );
                        },
                      ),
                    ),
                    if (activities.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '共 ${activities.length} 个活动，可下滑查看',
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: dontShowAgain,
                          onChanged: (value) {
                            setState(() {
                              dontShowAgain = value ?? false;
                            });
                          },
                        ),
                        const Text('不再提示此活动'),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    GStorage.putSetting(
                        SettingsKeys.activitiesUpdatedAt, maxUpdated);
                    KazumiDialog.dismiss();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '我知道了',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 活动详情弹窗（新格式）：标题 + 封面大图(充满) + 摘要 + 时间 + 自定义按钮(名字+跳转链接)
  static void _showActivityDetail(BuildContext context, ActivityItem item) {
    final cs = Theme.of(context).colorScheme;
    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.celebration, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.coverImage.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 200,
                        width: double.maxFinite,
                        child: Image.network(
                          item.coverImage,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              height: 200,
                              alignment: Alignment.center,
                              color: cs.surfaceContainerHighest,
                              child: const LoadingIndicator(),
                            );
                          },
                          errorBuilder: (context, error, stack) => Container(
                            height: 200,
                            alignment: Alignment.center,
                            color: cs.surfaceContainerHighest,
                            child: Text('图片加载失败',
                                style: TextStyle(fontSize: 12, color: cs.outline)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (item.summary.isNotEmpty)
                    Container(
                      width: double.maxFinite,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.summary,
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
                    ),
                  if (item.startTime.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '活动时间：${_shortDate(item.startTime)}'
                        '${item.endTime.isNotEmpty ? ' 至 ${_shortDate(item.endTime)}' : ''}',
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ),
                  // 自定义按钮：名字 + 点击跳转链接
                  if (item.linkUrl.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.maxFinite,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(
                          item.buttonText.isNotEmpty
                              ? item.buttonText
                              : '查看详情',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          final uri = Uri.tryParse(item.linkUrl);
                          if (uri != null) launchUrl(uri);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '我知道了',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 旧格式活动列表弹窗（version 锚点，兼容历史服务器）
  static void _showOldActivityDialog(List<Map<String, String>> activities, int version) {
    bool dontShowAgain = false;

    KazumiDialog.show(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.celebration, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('活动', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: activities.length,
                        itemBuilder: (context, index) {
                          final item = activities[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.campaign_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                              item['title'] ?? '活动',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => _showOldActivityDetail(context, item['title'] ?? '活动', item['content'] ?? ''),
                          );
                        },
                      ),
                    ),
                    if (activities.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '共 ${activities.length} 个活动，可下滑查看',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: dontShowAgain,
                          onChanged: (value) {
                            setState(() {
                              dontShowAgain = value ?? false;
                            });
                          },
                        ),
                        const Text('不再提示此活动'),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    GStorage.putSetting(SettingsKeys.announcementVersion, version);
                    KazumiDialog.dismiss();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '我知道了',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 旧格式活动详情弹窗：标题 + 内容(HTML 渲染，支持图片) + 我知道了
  static void _showOldActivityDetail(BuildContext context, String title, String content) {
    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.celebration, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isHtml(content))
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 460),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _HtmlContentView(htmlContent: content),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        content,
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '我知道了',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 新格式活动条目
class ActivityItem {
  final String id;
  final String title;
  final String summary;
  final String coverImage;
  final List<String> images;
  final String linkUrl;
  final String buttonText;
  final String startTime;
  final String endTime;
  final String createdAt;
  final String updatedAt;

  const ActivityItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.coverImage,
    required this.images,
    required this.linkUrl,
    required this.buttonText,
    required this.startTime,
    required this.endTime,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// HTML内容渲染组件（旧格式兼容）
class _HtmlContentView extends StatefulWidget {
  const _HtmlContentView({required this.htmlContent});

  final String htmlContent;

  @override
  State<_HtmlContentView> createState() => _HtmlContentViewState();
}

class _HtmlContentViewState extends State<_HtmlContentView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadHtmlString(_buildHtml(widget.htmlContent),
          baseUrl: 'https://qlyyz.xyz/');
  }

  String _buildHtml(String body) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 15px;
      line-height: 1.6;
      color: #333;
      padding: 12px;
      background: transparent;
    }
    img {
      max-width: 100%;
      height: auto;
      border-radius: 8px;
      margin: 8px 0;
    }
    a { color: #1976D2; text-decoration: none; }
    p { margin-bottom: 8px; }
    h1, h2, h3 { margin: 12px 0 8px; }
    ul, ol { padding-left: 20px; margin-bottom: 8px; }
    blockquote {
      border-left: 3px solid #1976D2;
      padding-left: 12px;
      margin: 8px 0;
      color: #666;
    }
  </style>
</head>
<body>$body</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(
            child: LoadingIndicator(),
          ),
      ],
    );
  }
}

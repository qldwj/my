import 'package:yhdm/bean/widget/loading_indicator.dart';
import 'dart:convert';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/services/storage/settings_keys.dart';
import 'package:yhdm/request/clients/download_http_client.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AnnouncementService {
  static const String _apiUrl = 'https://qlyyz.xyz/api/v0/notice?action=get';

  static Future<void> checkAnnouncement() async {
    try {
      final localVersion = GStorage.getSetting(SettingsKeys.announcementVersion) ?? 0;

      final client = DownloadHttpClient.instance;
      final response = await client.getPlain(_apiUrl);
      final data = json.decode(response) as Map<String, dynamic>;

      final version = data['version'] as int? ?? 0;
      // 活动列表：优先取 list 字段；兼容旧单条结构(title/content)
      final activities = <Map<String, String>>[];
      final rawList = data['list'];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is Map) {
            final t = (item['title'] ?? '').toString().trim();
            final c = (item['content'] ?? '').toString();
            final img = (item['image'] ?? item['img'] ?? item['pic'] ?? '').toString().trim();
            if (c.isNotEmpty) {
              activities.add({
                'title': t.isEmpty ? '活动' : t,
                'content': c,
                'image': img,
              });
            }
          }
        }
      } else {
        final t = (data['title'] ?? '活动').toString().trim();
        final c = (data['content'] ?? '').toString();
        final img = (data['image'] ?? data['img'] ?? data['pic'] ?? '').toString().trim();
        if (c.isNotEmpty) {
          activities.add({
            'title': t.isEmpty ? '活动' : t,
            'content': c,
            'image': img,
          });
        }
      }

      if (version > localVersion && activities.isNotEmpty) {
        _showActivityDialog(activities, version);
      }
    } catch (e) {
      KazumiLogger().w('Announcement: check failed', error: e);
    }
  }

  /// 判断内容是否为HTML
  static bool _isHtml(String content) {
    final trimmed = content.trim();
    return trimmed.startsWith('<') &&
        (trimmed.contains('</') || trimmed.contains('/>'));
  }

  /// 活动列表弹窗：默认展示最新 5 条，可下滑；点击条目展开详情(标题+内容+图片)。
  /// 点"我知道了"或勾选后仅记录当前 version，后台发布新活动(version 更新)仍会弹出。
  static void _showActivityDialog(List<Map<String, String>> activities, int version) {
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
                    // 活动列表：默认可视约 5 条，超出可下滑
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
                            onTap: () => _showActivityDetail(
                              context,
                              item['title'] ?? '活动',
                              item['content'] ?? '',
                              item['image'] ?? '',
                            ),
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
                    // 勾选/关闭均记录当前 version：后台发布新活动(version 更新)后仍会弹出
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

  /// 活动详情弹窗：标题 + 图片(补充) + 内容(HTML 渲染，支持图片) + 我知道了。
  static void _showActivityDetail(BuildContext context, String title, String content, String image) {
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
                  // 补充图片（可选）
                  if (image.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        image,
                        width: double.maxFinite,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            height: 160,
                            alignment: Alignment.center,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const LoadingIndicator(),
                          );
                        },
                        errorBuilder: (context, error, stack) => Container(
                          height: 80,
                          alignment: Alignment.center,
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Text(
                            '图片加载失败',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                          ),
                        ),
                      ),
                    ),
                  if (image.isNotEmpty) const SizedBox(height: 12),
                  if (_isHtml(content))
                    // HTML内容：用WebView渲染(支持图片/样式)
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
                    // 纯文本内容
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

/// HTML内容渲染组件
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
      // 🆕 加 baseUrl：否则部分 Android WebView 下图片/相对资源加载失败
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

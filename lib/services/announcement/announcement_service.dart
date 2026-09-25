import 'dart:convert';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AnnouncementService {
  static const String _apiUrl = 'https://qlyyz.xyz/api/notice?action=get';

  static Future<void> checkAnnouncement() async {
    try {
      final localVersion = GStorage.getSetting(SettingsKeys.announcementVersion) ?? 0;

      final client = DownloadHttpClient.instance;
      final response = await client.getPlain(_apiUrl);
      final data = json.decode(response) as Map<String, dynamic>;

      final version = data['version'] as int? ?? 0;
      final title = data['title'] as String? ?? '公告';
      final content = data['content'] as String? ?? '';

      if (version > localVersion && content.isNotEmpty) {
        _showAnnouncementDialog(title, content, version);
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

  static void _showAnnouncementDialog(String title, String content, int version) {
    bool dontShowAgain = false;

    KazumiDialog.show(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.announcement, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
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
                        // HTML内容：用WebView渲染
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
                      const SizedBox(height: 16),
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
                          const Text('不再提示此公告'),
                        ],
                      ),
                    ],
                  ),
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
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 网页版内嵌页面
/// 在 App 内直接加载网页版 yhdm，不用切换浏览器。
class WebviewEmbedPage extends StatefulWidget {
  const WebviewEmbedPage({super.key});
  @override
  State<WebviewEmbedPage> createState() => _WebviewEmbedPageState();
}

class _WebviewEmbedPageState extends State<WebviewEmbedPage> {
  late final WebViewController _controller;
  String _currentUrl = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final savedUrl = 'https://qlyyz.xyz/yhdm/';
    _currentUrl = savedUrl;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() { _isLoading = true; }),
        onPageFinished: (_) => setState(() { _isLoading = false; }),
      ))
      ..loadRequest(Uri.parse(savedUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: SysAppBar(
          title: const Text('网页版'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller.reload(),
            ),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

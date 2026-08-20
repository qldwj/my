import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart' show KazumiDialog;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:flutter_inappwebview_android/flutter_inappwebview_android.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

/// API9 登录源 · 内置 WebView 登录页
///
/// 在 App 内打开规则配置的 [loginUrl]，用户在内置浏览器中完成登录，
/// 检测到页面跳转离开登录页后自动抓取 Cookie 并保存。
class PluginLoginPage extends StatefulWidget {
  final String pluginName;
  final String loginUrl;
  const PluginLoginPage({super.key, required this.pluginName, required this.loginUrl});
  @override
  State<PluginLoginPage> createState() => _PluginLoginPageState();
}

class _PluginLoginPageState extends State<PluginLoginPage> {
  AndroidInAppWebViewController? _controller;
  final PlatformCookieManager _cookieManager =
      PlatformCookieManager(PlatformCookieManagerCreationParams());
  bool _saving = false;
  String _statusText = '正在加载登录页…';

  /// 登录成功检测：跳转离开 login 页即认为登录成功
  void _onLoadStop(String url) {
    if (_saving) return;
    if (!url.contains('login') && url.contains('http')) {
      _statusText = '登录成功，正在保存…';
      setState(() {});
      _finishAndSave(url);
    }
  }

  Future<void> _finishAndSave(String currentUrl) async {
    if (_saving) return;
    _saving = true;
    try {
      final uri = Uri.parse(currentUrl);
      final hostUrl = 'https://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      final cookies = await _cookieManager.getCookies(url: WebUri(hostUrl));
      final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ').trim();
      if (cookieStr.isEmpty) {
        KazumiDialog.showToast(message: '⚠️ 未获取到 Cookie，请确认已登录');
        _statusText = '请确认已登录后点「完成」';
        setState(() {});
        return;
      }
      await PluginCookieManager.instance.saveFromWebView(widget.pluginName, currentUrl, cookieStr);
      KazumiDialog.showToast(message: '✅ 登录成功，共保存 ${cookies.length} 条 Cookie');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      KazumiLogger().e('[PluginLoginPage] 保存失败', error: e);
      KazumiDialog.showToast(message: '❌ 保存失败: $e');
    } finally { _saving = false; }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(canPop: true, child: Scaffold(
      appBar: SysAppBar(
        title: Text('登录「${widget.pluginName}」'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () {
              if (_controller != null) {
                _controller!.getUrl().then((url) {
                  if (url != null) _finishAndSave(url.toString());
                });
              }
            },
            child: Text('完成', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        // 状态栏
        Container(
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(_statusText, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        // WebView
        Expanded(
          child: AndroidInAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.loginUrl)),
            initialSettings: InAppWebViewSettings(
              userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: true,
              cacheEnabled: true,
              loadWithOverviewMode: true,
              useWideViewPort: true,
            ),
            onWebViewCreated: (controller) { _controller = controller; },
            onLoadStop: (controller, url) { _onLoadStop(url.toString()); },
            onConsoleMessage: (controller, consoleMessage) {
              KazumiLogger().i('[PluginLogin] console: ${consoleMessage.message}');
            },
          ),
        ),
      ]),
    ));
  }
}
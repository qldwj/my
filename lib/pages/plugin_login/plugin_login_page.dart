import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart' show KazumiDialog;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

/// API9 登录源 · 内置浏览器登录页
///
/// 在应用内打开规则配置的 [loginUrl]，用户完成登录（账号/密码、
/// 验证码、扫码等）后点击「完成」，抓取当前站点 Cookie 并
/// 保存到 [PluginCookieManager]，后续搜索/章节/播放请求自动携带。
class PluginLoginPage extends StatefulWidget {
  final String pluginName;
  final String loginUrl;

  const PluginLoginPage({
    super.key,
    required this.pluginName,
    required this.loginUrl,
  });

  @override
  State<PluginLoginPage> createState() => _PluginLoginPageState();
}

class _PluginLoginPageState extends State<PluginLoginPage> {
  PlatformInAppWebViewController? _controller;
  final PlatformCookieManager _cookieManager =
      PlatformCookieManager(PlatformCookieManagerCreationParams());
  bool _saving = false;
  String _currentUrl = '';

  Future<void> _captureUrl() async {
    try {
      final url = await _controller?.getUrl();
      if (url != null) _currentUrl = url.toString();
    } catch (_) {}
  }

  /// 抓取当前站点 cookie 并保存到规则 cookie 管理器
  Future<void> _finishAndSave() async {
    if (_saving) return;
    _saving = true;

    try {
      await _captureUrl();
      var targetUrl = _currentUrl;
      if (targetUrl.isEmpty || targetUrl == 'about:blank') {
        targetUrl = widget.loginUrl;
      }
      final uri = Uri.tryParse(targetUrl);
      if (uri == null || uri.host.isEmpty) {
        KazumiDialog.showToast(message: '⚠️ 无法确定站点地址');
        return;
      }

      final cookies = await _cookieManager.getCookies(
        url: WebUri('https://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'),
      );
      final cookieStr =
          cookies.map((c) => '${c.name}=${c.value}').join('; ').trim();

      if (cookieStr.isEmpty) {
        KazumiLogger().w(
            '[PluginLoginPage] 未获取到 Cookie（可能尚未完成登录）: ${uri.host}');
        KazumiDialog.showToast(
            message: '⚠️ 未获取到登录信息，请确认已登录后点「完成」');
        return;
      }

      await PluginCookieManager.instance.saveFromWebView(
        widget.pluginName,
        targetUrl,
        cookieStr,
      );
      KazumiDialog.showToast(message: '✅ 登录信息已保存，共 ${cookies.length} 条');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      KazumiLogger().e('[PluginLoginPage] 保存登录信息失败', error: e);
      KazumiDialog.showToast(message: '❌ 保存失败: $e');
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: SysAppBar(
          title: Text('登录「${widget.pluginName}」'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _finishAndSave,
              child: Text(
                _saving ? '保存中…' : '登录完成',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                '请在下方页面完成登录，登录成功后点右上角「登录完成」',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: PlatformInAppWebView(
                PlatformInAppWebViewCreationParams(
                  initialSettings: InAppWebViewSettings(
                    userAgent: getRandomUA(),
                    mediaPlaybackRequiresUserGesture: true,
                    cacheEnabled: true,
                    blockNetworkImage: false,
                    loadsImagesAutomatically: true,
                    upgradeKnownHostsToHTTPS: false,
                    safeBrowsingEnabled: false,
                    javaScriptCanOpenWindowsAutomatically: true,
                  ),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    // 创建后立即加载登录页
                    try {
                      controller.loadUrl(
                        urlRequest: URLRequest(url: WebUri(widget.loginUrl)),
                      );
                    } catch (e) {
                      KazumiLogger().e('[PluginLoginPage] 加载登录页失败',
                          error: e);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
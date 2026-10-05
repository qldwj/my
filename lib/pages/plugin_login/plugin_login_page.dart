import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart' show KazumiDialog;
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/plugin/plugin_cookie_manager.dart';
import 'package:yhdm/services/plugin/plugin_credential_store.dart';
import 'package:yhdm/plugins/plugins.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// API9 登录源 · 内置 WebView 登录 + 本地保存账号密码
///
/// 1. WebView 登录：用户在内置浏览器登录，登录成功自动抓取 Cookie 保存
/// 2. 保存账号密码：勾选「记住密码」后保存到本地
/// 3. Cookie 过期后：自动用保存的账号调用 auth/login 刷新（用户无感知）
class PluginLoginPage extends StatefulWidget {
  final Plugin plugin;
  const PluginLoginPage({super.key, required this.plugin});
  @override
  State<PluginLoginPage> createState() => _PluginLoginPageState();
}

class _PluginLoginPageState extends State<PluginLoginPage> {
  late final WebViewController _webViewController;
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _saving = false;
  bool _rememberPassword = false;
  String _statusText = '正在加载登录页…';

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36')
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          // 排除初始 loginUrl：如次元城 loginUrl 是首页（不含 'login'），
          // 旧逻辑一打开就误判"登录成功"自动保存，而用户还没登录，之后只得手动点保存。
          if (url != widget.plugin.loginUrl &&
              !url.contains('login') &&
              url.contains('http') &&
              !_saving) {
            _statusText = '登录成功，正在保存…';
            setState(() {});
            _finishAndSave(url);
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.plugin.loginUrl));
    // 加载已保存的账号密码
    final cred = PluginCredentialStore.instance.load(widget.plugin.name);
    if (cred != null) {
      _usernameCtrl.text = cred.$1;
      _passwordCtrl.text = cred.$2;
      _rememberPassword = true;
    }
  }

  Future<void> _finishAndSave(String currentUrl) async {
    if (_saving) return;
    _saving = true;
    try {
      final uri = Uri.parse(currentUrl);
      final hostUrl = Uri(scheme: 'https', host: uri.host, port: uri.port);
      // SPA 站通常将 auth token 存在 localStorage 而非 cookie
      // 同时获取 localStorage 中的 token 信息，组装成 cookie 格式
      String cookieStr = '';
      try {
        // 先尝试 document.cookie
        final raw = await _webViewController.runJavaScriptReturningResult('document.cookie');
        cookieStr = raw.toString().replaceAll('"', '').trim();
        // 再从 localStorage 找 token（SPA 常见 key）
        final lsRaw = await _webViewController.runJavaScriptReturningResult(
            "(() => {"
            "  const entries = [];"
            "  for(let i=0;i<localStorage.length;i++){"
            "    const k = localStorage.key(i);"
            "    const v = localStorage.getItem(k);"
            "    if(v && k.toLowerCase().includes('token')) entries.push(k+'='+v);"
            "  }"
            "  return entries.join('; ');"
            "})()");
        final lsToken = lsRaw.toString().replaceAll('"', '').trim();
        if (lsToken.isNotEmpty) {
          cookieStr = cookieStr.isNotEmpty ? '$cookieStr; $lsToken' : lsToken;
        }
      } catch (e) {
        KazumiLogger().w('[PluginLoginPage] Cookie 获取异常: $e');
      }
      if (cookieStr.trim().isEmpty) {
        // 调试：显示所有 localStorage key，帮用户定位 token 存在哪
        try {
          final allKeys = await _webViewController.runJavaScriptReturningResult(
              "JSON.stringify(Object.keys(localStorage))");
          _statusText = '未获取到登录信息。localStorage keys: $allKeys';
          KazumiDialog.showToast(message: '⚠️ 未获取到 Token，请截图 localStorage keys');
        } catch (_) {
          _statusText = '未获取到登录信息，请确认已登录';
        }
        setState(() {});
        _saving = false;
        return;
      }
      await PluginCookieManager.instance.saveFromWebView(widget.plugin.name, currentUrl, cookieStr);
      // 注入 Authorization header 到规则（SPA API 需要 Bearer token）
      try {
        final tokenPair = cookieStr.split('; ').firstWhere(
          (s) => s.toLowerCase().contains('token'), orElse: () => '');
        if (tokenPair.isNotEmpty) {
          final tokenValue = tokenPair.split('=').skip(1).join('=');
          widget.plugin.searchApiConfig.request.headers['Authorization'] = 'Bearer $tokenValue';
          widget.plugin.chapterApiConfig.request.headers['Authorization'] = 'Bearer $tokenValue';
        }
      } catch (_) {}
      if (_rememberPassword && _usernameCtrl.text.isNotEmpty && _passwordCtrl.text.isNotEmpty) {
        await PluginCredentialStore.instance.save(widget.plugin.name, _usernameCtrl.text, _passwordCtrl.text);
      }
      KazumiDialog.showToast(message: '✅ 登录成功');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      KazumiLogger().e('[PluginLoginPage] 保存失败', error: e);
      KazumiDialog.showToast(message: '❌ 保存失败: $e');
    } finally { _saving = false; }
  }

  @override
  void dispose() { _usernameCtrl.dispose(); _passwordCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(canPop: true, child: Scaffold(
      appBar: SysAppBar(
        title: Text('登录「${widget.plugin.name}」'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () async {
              final url = await _webViewController.currentUrl();
              if (url != null) _finishAndSave(url);
            },
            child: Text('完成', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(_statusText, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Expanded(child: WebViewWidget(controller: _webViewController)),
      ]),
    ));
  }
}
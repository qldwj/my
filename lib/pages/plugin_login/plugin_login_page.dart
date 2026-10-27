import 'dart:async';
import 'dart:convert';
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
      // 🆕 监听登录 token 出现：SPA 登录后 URL 不变，onPageStarted 不会触发，
      // 改用 JS 轮询 localStorage，检测到有效 token 自动保存（无需手动点「完成」）。
      ..addJavaScriptChannel('LoginChannel',
          onMessageReceived: (msg) async {
            if (_saving || !mounted) return;
            final data = msg.message;
            // 校验 token 非空
            try {
              final decoded = jsonDecode(data);
              if (decoded is Map) {
                final t = decoded['token'];
                if (t is! String || t.trim().isEmpty) return;
              } else {
                return;
              }
            } catch (_) {
              return;
            }
            final url = await _webViewController.currentUrl();
            if (url == null) return;
            _statusText = '检测到登录信息，正在保存…';
            if (mounted) setState(() {});
            _finishAndSave(url);
          })
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
        // 🆕 每次页面加载完成后注入 token 轮询脚本
        onPageFinished: (url) {
          _injectTokenPoller();
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

  /// 🆕 注入 token 轮询脚本：检测 localStorage 中出现非空 token 时
  /// 通过 LoginChannel 通知 Dart 自动保存。SPA 登录后 URL 不变，
  /// onPageStarted 无法感知登录成功，需靠此轮询。
  Future<void> _injectTokenPoller() async {
    try {
      const script = r'''
        (() => {
          if (window.__cycLoginPollerActive) return;
          window.__cycLoginPollerActive = true;
          const poll = () => {
            try {
              for (let i = 0; i < localStorage.length; i++) {
                const k = localStorage.key(i);
                const v = localStorage.getItem(k);
                if (!v) continue;
                try {
                  const obj = JSON.parse(v);
                  if (obj && typeof obj === 'object' &&
                      typeof obj.token === 'string' && obj.token.trim() !== '') {
                    window.LoginChannel.postMessage(JSON.stringify({ token: obj.token, expiresAt: obj.expiresAt || '' }));
                    clearInterval(window.__cycLoginPollTimer);
                    window.__cycLoginPollerActive = false;
                    return;
                  }
                } catch (_) {}
                if (k.toLowerCase().includes('token') && typeof v === 'string' && v.trim() !== '') {
                  window.LoginChannel.postMessage(JSON.stringify({ token: v, expiresAt: '' }));
                  clearInterval(window.__cycLoginPollTimer);
                  window.__cycLoginPollerActive = false;
                  return;
                }
              }
            } catch (_) {}
          };
          window.__cycLoginPollTimer = setInterval(poll, 500);
        })();
      ''';
      await _webViewController.runJavaScript(script);
    } catch (e) {
      KazumiLogger().w('[PluginLoginPage] 注入 token 轮询失败: $e');
    }
  }

  /// 🆕 粘贴自己的 Cookie 并保存（内置浏览器抓取不准时的兜底）
  Future<void> _pasteCookie() async {
    final ctrl = TextEditingController();
    final result = await KazumiDialog.show<String>(
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴 Cookie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('把浏览器里复制到的 Cookie 字符串粘贴进来（形如 a=1; b=2）。',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '在此粘贴 Cookie',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => KazumiDialog.dismiss(popWith: ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;

    _saving = true;
    setState(() => _statusText = '正在保存粘贴的 Cookie…');
    try {
      final url = await _webViewController.currentUrl() ?? widget.plugin.loginUrl;
      final uri = Uri.parse(url);
      final hostUrl = Uri(scheme: 'https', host: uri.host, port: uri.port).toString();
      await PluginCookieManager.instance
          .saveFromWebView(widget.plugin.name, hostUrl, result);
      final st = PluginCookieManager.instance.cookieStatus(widget.plugin.name);
      final valid = st['valid'] == true;
      final expiresAt = st['expiresAt'] as DateTime?;
      if (!mounted) return;
      KazumiDialog.showToast(
        message: valid
            ? '✅ Cookie 已保存${expiresAt != null ? '，有效期至 ${expiresAt.toLocal()}' : ''}'
            : '⚠️ Cookie 已保存，但可能已过期（无 expires 或已超时）',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      KazumiLogger().e('[PluginLoginPage] 粘贴 Cookie 保存失败', error: e);
      _saving = false;
      if (mounted) {
        setState(() => _statusText = '保存失败：$e');
        KazumiDialog.showToast(message: '❌ 保存失败: $e');
      }
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
      String? authToken;
      DateTime? tokenExpiresAt;
      try {
        // 先尝试 document.cookie
        final raw = await _webViewController.runJavaScriptReturningResult('document.cookie');
        cookieStr = raw.toString().replaceAll('"', '').trim();
        // 从 localStorage 找 token（SPA 常见 key）。
        // 可能是 JSON（如次元城 cycweb:auth:v2 = {token, expiresAt, ...}），
        // 也可能是 key/value 直接含 token。
        final lsRaw = await _webViewController.runJavaScriptReturningResult(
            "(() => {"
            "  const result = { token: '', expiresAt: '' };"
            "  for(let i=0;i<localStorage.length;i++){"
            "    const k = localStorage.key(i);"
            "    const v = localStorage.getItem(k);"
            "    if(!v) continue;"
            "    try {"
            "      const obj = JSON.parse(v);"
            "      if(obj && typeof obj === 'object' && obj.token) {"
            "        if(!result.token) result.token = obj.token;"
            "        if(!result.expiresAt && obj.expiresAt) result.expiresAt = obj.expiresAt;"
            "        continue;"
            "      }"
            "    } catch(_) {}"
            "    if(k.toLowerCase().includes('token')) {"
            "      if(!result.token) result.token = v;"
            "    }"
            "  }"
            "  return JSON.stringify(result);"
            "})()");
        final lsStr = lsRaw.toString().trim();
        if (lsStr.isNotEmpty) {
          // runJavaScriptReturningResult 对字符串返回值做了 JSON 包装，
          // 需先解出内层字符串再解析。
          String? lsPayload;
          try {
            final first = jsonDecode(lsStr);
            lsPayload = first is String ? first : jsonEncode(first);
          } catch (_) {
            lsPayload = lsStr.replaceAll('"', '');
          }
          if (lsPayload != null && lsPayload.isNotEmpty) {
            try {
              final lsObj = jsonDecode(lsPayload);
              if (lsObj is Map) {
                final t = lsObj['token'];
                if (t is String && t.isNotEmpty) authToken = t;
                final e = lsObj['expiresAt'];
                if (e is String && e.isNotEmpty) {
                  tokenExpiresAt = DateTime.tryParse(e);
                }
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        KazumiLogger().w('[PluginLoginPage] Cookie 获取异常: $e');
      }
      if (cookieStr.trim().isEmpty && (authToken == null || authToken!.isEmpty)) {
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
      // 🆕 token 认证站点：单独保存 token（供 check 接口校验登录态）
      final savedToken = authToken ?? PluginCookieManager.instance.tokenFor(widget.plugin.name);
      if (savedToken != null && savedToken.isNotEmpty) {
        await PluginCookieManager.instance.saveToken(
          widget.plugin.name,
          savedToken,
          expiresAt: tokenExpiresAt,
        );
      }
      // 注入 Authorization header 到规则（SPA API 需要 Bearer token）
      if (savedToken != null && savedToken.isNotEmpty) {
        try {
          widget.plugin.searchApiConfig.request.headers['Authorization'] = 'Bearer $savedToken';
          widget.plugin.chapterApiConfig.request.headers['Authorization'] = 'Bearer $savedToken';
        } catch (_) {}
      } else {
        // 无 token 时回退到从 cookie 里找（老逻辑）
        try {
          final tokenPair = cookieStr.split('; ').firstWhere(
            (s) => s.toLowerCase().contains('token'), orElse: () => '');
          if (tokenPair.isNotEmpty) {
            final tokenValue = tokenPair.split('=').skip(1).join('=');
            widget.plugin.searchApiConfig.request.headers['Authorization'] = 'Bearer $tokenValue';
            widget.plugin.chapterApiConfig.request.headers['Authorization'] = 'Bearer $tokenValue';
          }
        } catch (_) {}
      }
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
          // 🆕 粘贴 Cookie：直接从剪贴板粘贴自己的 Cookie（内置浏览器抓取不准时的兜底）
          IconButton(
            tooltip: '粘贴 Cookie',
            icon: const Icon(Icons.content_paste_rounded),
            onPressed: _saving ? null : _pasteCookie,
          ),
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
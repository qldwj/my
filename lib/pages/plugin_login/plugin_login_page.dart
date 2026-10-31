import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart' show KazumiDialog;
import 'package:yhdm/request/core/dio_factory.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/plugin/plugin_cookie_manager.dart';
import 'package:yhdm/services/plugin/plugin_credential_store.dart';
import 'package:yhdm/services/plugin/plugin_login_check_service.dart';
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
            // 区分两类消息：xpath 登录成功信号 / token 出现。
            String? detectedToken;
            bool xpathSuccess = false;
            try {
              final decoded = jsonDecode(data);
              if (decoded is Map) {
                if (decoded['xpathSuccess'] == true) {
                  xpathSuccess = true;
                } else {
                  final t = decoded['token'];
                  if (t is! String || t.trim().isEmpty) return;
                  detectedToken = t;
                }
              } else {
                return;
              }
            } catch (_) {
              return;
            }
            final url = await _webViewController.currentUrl();
            if (url == null) return;
            // xpath 登录成功：页面已出现登录态特征，直接保存（跳过 token 校验）。
            if (xpathSuccess) {
              _statusText = '检测到登录成功特征，正在保存…';
              if (mounted) setState(() {});
              _finishAndSave(url);
              return;
            }
            // 🆕 检测到 token 后先过规则 check 校验再保存，防止把站点预置的
            // 干扰 token（游客态/设备 token）误当成登录态保存，导致未登录就标记
            // 成功、后续 check 401 反复弹登录（死循环）。校验通过才保存。
            if (widget.plugin.usesApiCheck) {
              final check = await PluginLoginCheckService.instance
                  .checkToken(widget.plugin, detectedToken!);
              if (!check.valid) {
                _statusText = '检测到 token 但校验未通过（${check.message ?? '无效'}），请确认已登录后点「完成」';
                if (mounted) setState(() {});
                return;
              }
            }
            _statusText = '检测到登录信息，正在保存…';
            if (mounted) setState(() {});
            _finishAndSave(url);
          })
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          // 仅独立登录页（loginURL 含 'login'，如次元城 /login）才启用「跳转即登录成功」
          // 自动保存。SPA 弹窗登录站（loginURL 为首页、不含 'login'，如 sorani）不适用
          // 此假设——打开页面或任意 URL 波动都会被误判为登录成功，导致未登录就保存
          // 无效 token（随后 check 401 反复弹登录，形成死循环）。这类站点改由
          // token 轮询（先过 check 校验）+ 用户点「完成」触发保存。
          final hasDedicatedLoginPage = widget.plugin.loginUrl.contains('login');
          if (hasDedicatedLoginPage &&
              url != widget.plugin.loginUrl &&
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

  /// 🆕 xpath 登录（`login.mode == 'xpath'`）：用输入的账号密码自动填入登录表单
  /// 并提交，成功后靠 [successXpath] 特征轮询自动保存。
  Future<void> _autoFillXpathLogin() async {
    final account = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final cfg = widget.plugin.loginConfig;
    if (cfg == null) return;
    if (account.isEmpty || password.isEmpty) {
      KazumiDialog.showToast(message: '请先输入账号和密码');
      return;
    }
    if (cfg.accountXpath.isEmpty || cfg.passwordXpath.isEmpty) {
      KazumiDialog.showToast(message: '规则未配置账号/密码 XPath');
      return;
    }
    setState(() => _statusText = '正在填入登录表单…');
    try {
      final accJs = jsonEncode(cfg.accountXpath);
      final pwdJs = jsonEncode(cfg.passwordXpath);
      final accVal = jsonEncode(account);
      final pwdVal = jsonEncode(password);
      final fillScript = '''
        (() => {
          const setVal = (xpath, val) => {
            const el = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
            if (!el) return false;
            const proto = Object.getPrototypeOf(el);
            const desc = Object.getOwnPropertyDescriptor(proto, 'value');
            if (desc && desc.set) { desc.set.call(el, val); } else { el.value = val; }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            return true;
          };
          const ok1 = setVal($accJs, $accVal);
          const ok2 = setVal($pwdJs, $pwdVal);
          return JSON.stringify({ ok: ok1 && ok2 });
        })()
      ''';
      final r =
          await _webViewController.runJavaScriptReturningResult(fillScript);
      final ok = r.toString().contains('"ok":true');
      if (!ok) {
        setState(() => _statusText = '未找到登录表单元素，请确认 XPath 正确');
        return;
      }
      if (cfg.submitXpath.isNotEmpty) {
        final subJs = jsonEncode(cfg.submitXpath);
        await _webViewController.runJavaScript('''
          (() => {
            const el = document.evaluate($subJs, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
            if (el) el.click();
          })()
        ''');
      }
      setState(() => _statusText = '已提交，等待登录成功…');
      if (cfg.successXpath.isNotEmpty) {
        await _startXpathSuccessPoller(cfg.successXpath);
      }
    } catch (e) {
      KazumiLogger().w('[PluginLoginPage] xpath 登录失败: $e');
      setState(() => _statusText = '自动填入失败：$e');
    }
  }

  /// 🆕 xpath 登录成功特征轮询：页面出现 [successXpath] 节点即视为登录成功。
  Future<void> _startXpathSuccessPoller(String successXpath) async {
    try {
      final successJs = jsonEncode(successXpath);
      final script = '''
        (() => {
          if (window.__xpathLoginPollerActive) return;
          window.__xpathLoginPollerActive = true;
          const check = () => {
            const el = document.evaluate($successJs, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
            if (el) {
              window.LoginChannel.postMessage(JSON.stringify({ xpathSuccess: true }));
              clearInterval(window.__xpathLoginPollTimer);
              window.__xpathLoginPollerActive = false;
            }
          };
          window.__xpathLoginPollTimer = setInterval(check, 800);
        })()
      ''';
      await _webViewController.runJavaScript(script);
    } catch (e) {
      KazumiLogger().w('[PluginLoginPage] xpath 成功轮询注入失败: $e');
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

  /// 🆕 API 登录（`login.mode == 'api'`）：用输入的账号密码直接调用登录接口，
  /// 从响应提取 token/cookie 保存。用于无独立登录页的 SPA 登录站。
  Future<void> _apiLogin() async {
    final account = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (account.isEmpty || password.isEmpty) {
      KazumiDialog.showToast(message: '请先输入账号和密码');
      return;
    }
    final loginApi = widget.plugin.loginConfig?.api;
    if (loginApi == null) return;
    final req = loginApi.request;
    _saving = true;
    setState(() => _statusText = '正在调用登录接口…');
    try {
      final url = req.url
          .replaceAll('@account', account)
          .replaceAll('@password', password);
      final query = _renderApiMap(req.query, account, password);
      final headers = _renderApiMap(req.headers, account, password);
      final body = _renderApiBody(req.body, account, password);
      final response = await DioFactory.pluginDio.request<String>(
        url,
        queryParameters: query.isEmpty ? null : query,
        options: Options(
          method: req.method.toUpperCase(),
          responseType: ResponseType.plain,
          headers: headers,
        ),
        data: body,
      );
      final statusOk = response.statusCode == loginApi.successStatus;
      final decoded = _tryDecode(response.data);
      final codeOk = loginApi.successCode == null ||
          _readJsonPath(decoded, loginApi.successCodePath) == loginApi.successCode;
      if (!statusOk || !codeOk) {
        setState(() => _statusText =
            '登录失败（HTTP ${response.statusCode}${codeOk ? '' : '，业务码不匹配'}）');
        return;
      }
      final token = loginApi.tokenPath.isNotEmpty
          ? _readJsonPath(decoded, loginApi.tokenPath)
          : null;
      final cookie = loginApi.cookiePath.isNotEmpty
          ? _readJsonPath(decoded, loginApi.cookiePath)
          : null;
      if ((token is! String || token.isEmpty) &&
          (cookie is! String || cookie.isEmpty)) {
        setState(() => _statusText =
            '登录成功但未提取到 token/cookie，请检查 tokenPath/cookiePath');
        return;
      }
      if (token is String && token.isNotEmpty) {
        await PluginCookieManager.instance.saveToken(widget.plugin.name, token);
      }
      if (cookie is String && cookie.isNotEmpty) {
        await PluginCookieManager.instance.saveFromWebView(
            widget.plugin.name, widget.plugin.loginUrl, cookie);
      }
      final savedToken = token is String && token.isNotEmpty
          ? token
          : PluginCookieManager.instance.tokenFor(widget.plugin.name);
      if (savedToken != null && savedToken.isNotEmpty) {
        widget.plugin.searchApiConfig.request.headers['Authorization'] =
            'Bearer $savedToken';
        widget.plugin.chapterApiConfig.request.headers['Authorization'] =
            'Bearer $savedToken';
      }
      if (_rememberPassword && account.isNotEmpty && password.isNotEmpty) {
        await PluginCredentialStore.instance
            .save(widget.plugin.name, account, password);
      }
      KazumiDialog.showToast(message: '✅ 登录成功');
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      setState(() => _statusText =
          '登录失败（HTTP ${status ?? '网络异常'}）：${e.message}');
    } catch (e) {
      KazumiLogger().e('[PluginLoginPage] API 登录失败', error: e);
      setState(() => _statusText = '登录失败：$e');
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  /// 🆕 渲染 Map 中字符串值的 @account/@password 占位符。
  Map<String, dynamic> _renderApiMap(
    Map<String, dynamic> source,
    String account,
    String password,
  ) {
    if (source.isEmpty) return const {};
    return source.map((key, value) {
      if (value is String) {
        return MapEntry(
            key, value.replaceAll('@account', account).replaceAll('@password', password));
      }
      return MapEntry(key, value);
    });
  }

  /// 🆕 渲染 body（String 或 Map）中的 @account/@password 占位符。
  dynamic _renderApiBody(dynamic body, String account, String password) {
    if (body is String) {
      return body.replaceAll('@account', account).replaceAll('@password', password);
    }
    if (body is Map) {
      return body.map((key, value) {
        if (value is String) {
          return MapEntry(
              key, value.replaceAll('@account', account).replaceAll('@password', password));
        }
        return MapEntry(key, value);
      });
    }
    return body;
  }

  /// 🆕 按 JSONPath（如 `$.data.token`）读取值；空路径回退顶层。
  dynamic _readJsonPath(dynamic root, String path) {
    if (path.isEmpty) return root;
    final normalized = path.startsWith('$') ? path.substring(1) : path;
    dynamic current = root;
    for (final part in normalized.split('.')) {
      final key = part.trim();
      if (key.isEmpty) continue;
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  /// 🆕 安全解析 JSON 响应体。
  dynamic _tryDecode(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
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

  /// 🆕 登录面板：`login.mode == 'xpath'/'api'` 时显示账号密码输入与登录按钮。
  Widget _buildLoginPanel(ThemeData theme) {
    final cfg = widget.plugin.loginConfig!;
    final isApi = cfg.isApi;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isApi
                ? 'API 登录：填写账号密码后点「API 登录」'
                : '自动登录：填写账号密码后点「自动填入并登录」',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              labelText: '账号',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: _rememberPassword,
                onChanged: (v) =>
                    setState(() => _rememberPassword = v ?? false),
              ),
              const Text('记住密码', style: TextStyle(fontSize: 12)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : (isApi ? _apiLogin : _autoFillXpathLogin),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: Text(isApi ? 'API 登录' : '自动填入并登录'),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
        if (widget.plugin.loginConfig != null &&
            !widget.plugin.loginConfig!.isWebview)
          _buildLoginPanel(theme),
        Expanded(child: WebViewWidget(controller: _webViewController)),
      ]),
    ));
  }
}
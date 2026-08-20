import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart' show KazumiDialog;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:kazumi/services/plugin/plugin_credential_store.dart';
import 'package:flutter_inappwebview_android/flutter_inappwebview_android.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

/// API9 登录源 · 内置 WebView 登录 + 本地保存账号密码
///
/// 1. WebView 登录：用户在内置浏览器登录，登录成功自动抓取 Cookie 保存
/// 2. 保存账号密码：勾选「记住密码」后，保存到本地 Hive
/// 3. Cookie 过期后：自动用保存的账号调用 /api/auth/login 刷新（用户无感知）
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
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _saving = false;
  bool _rememberPassword = false;
  String _statusText = '正在加载登录页…';

  @override
  void initState() {
    super.initState();
    // 加载已保存的账号密码（如果有）
    final cred = PluginCredentialStore.instance.load(widget.pluginName);
    if (cred != null) {
      _usernameCtrl.text = cred.$1;
      _passwordCtrl.text = cred.$2;
      _rememberPassword = true;
    }
  }

  /// 登录成功检测：跳转离开 login 页
  void _onLoadStop(String url) {
    if (_saving) return;
    if (!url.contains('login') && url.contains('http')) {
      _statusText = '登录成功，正在保存…';
      setState(() {});
      _finishAndSave(url);
    }
  }

  /// 抓取 Cookie 并保存（+ 可选保存账号密码）
  Future<void> _finishAndSave(String currentUrl) async {
    if (_saving) return;
    _saving = true;
    try {
      final uri = Uri.parse(currentUrl);
      final hostUrl = 'https://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      final cookies = await _cookieManager.getCookies(url: WebUri(hostUrl));
      final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ').trim();
      if (cookieStr.isEmpty) {
        _statusText = '请确认已登录后点「完成」';
        setState(() {});
        _saving = false;
        return;
      }
      await PluginCookieManager.instance.saveFromWebView(widget.pluginName, currentUrl, cookieStr);
      // 保存账号密码（如果有填写）
      if (_rememberPassword && _usernameCtrl.text.isNotEmpty && _passwordCtrl.text.isNotEmpty) {
        await PluginCredentialStore.instance.save(
            widget.pluginName, _usernameCtrl.text, _passwordCtrl.text);
      }
      KazumiDialog.showToast(message: '✅ 登录成功，共保存 ${cookies.length} 条');
      if (mounted) Navigator.of(context).pop();
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
        title: Text('登录「${widget.pluginName}」'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () async {
              if (_controller != null) {
                final url = await _controller!.getUrl();
                if (url != null) _finishAndSave(url.toString());
              }
            },
            child: Text('完成', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        // 状态提示
        Container(
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(_statusText, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        // WebView
        Expanded(
          child: InAppWebView(
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
          ),
        ),
        // 保存账号密码区域
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(child: TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(hintText: '账号（邮箱/用户名）', border: OutlineInputBorder(), isDense: true),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: '密码', border: OutlineInputBorder(), isDense: true),
                )),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Checkbox(
                  value: _rememberPassword,
                  onChanged: (v) => setState(() => _rememberPassword = v ?? false),
                ),
                Text('保存账号密码（Cookie 过期后自动登录）',
                    style: theme.textTheme.bodySmall),
              ]),
            ],
          ),
        ),
      ]),
    ));
  }
}

import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart' show KazumiDialog;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:url_launcher/url_launcher.dart';

/// API9 登录源 · 粘贴 Cookie 方案
///
/// 点击「打开浏览器登录」→ 在系统浏览器登录 → 回到 App
/// 在下方文本框粘贴 Cookie 字符串 → 保存后请求自动携带。
class PluginLoginPage extends StatefulWidget {
  final String pluginName;
  final String loginUrl;
  const PluginLoginPage({super.key, required this.pluginName, required this.loginUrl});
  @override
  State<PluginLoginPage> createState() => _PluginLoginPageState();
}

class _PluginLoginPageState extends State<PluginLoginPage> {
  final TextEditingController _cookieController = TextEditingController();
  bool _saving = false;

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.loginUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      KazumiDialog.showToast(message: '无法打开浏览器');
    }
  }

  Future<void> _saveCookie() async {
    final cookieStr = _cookieController.text.trim();
    if (cookieStr.isEmpty) { KazumiDialog.showToast(message: 'Cookie 不能为空'); return; }
    if (_saving) return;
    _saving = true;
    try {
      await PluginCookieManager.instance.saveFromWebView(widget.pluginName, widget.loginUrl, cookieStr);
      KazumiDialog.showToast(message: '登录信息已保存');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      KazumiLogger().e('[PluginLoginPage] 保存失败', error: e);
      KazumiDialog.showToast(message: '保存失败: $e');
    } finally { _saving = false; }
  }

  @override
  void dispose() { _cookieController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(canPop: true, child: Scaffold(
      appBar: SysAppBar(title: Text('登录「${widget.pluginName}」')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('步骤说明', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _step('1', '打开浏览器登录', '在系统浏览器中完成账号登录'),
          _step('2', '复制 Cookie', '登录后在浏览器地址栏输入：\njavascript:document.title=document.cookie\n然后复制地址栏显示的内容'),
          _step('3', '粘贴并保存', '回到本页粘贴 Cookie 字符串，点击保存'),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _openInBrowser, icon: const Icon(Icons.open_in_browser), label: const Text('打开浏览器登录'),
          )),
          const SizedBox(height: 20),
          Text('粘贴 Cookie', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(controller: _cookieController, maxLines: 3, minLines: 2,
            decoration: const InputDecoration(hintText: '例: token=xxx; session=yyy', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _saving ? null : _saveCookie,
            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            label: Text(_saving ? '保存中…' : '保存'),
          )),
          const SizedBox(height: 20),
          Card(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), child: Padding(
            padding: const EdgeInsets.all(12), child: Text(
              'Cookie 仅保存在本设备，不上传任何服务器。重启 App 后可能需要重新粘贴。',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )),
        ],
      )),
    ));
  }

  Widget _step(String num, String title, String desc) => Padding(
    padding: const EdgeInsets.only(bottom: 10), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 12, child: Text(num, style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ])),
      ],
    ),
  );
}
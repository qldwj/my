import 'dart:async';
import "package:yhdm/pages/plugin_editor/mcp_server_dialog.dart";
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/services/tutorial/tutorial_steps.dart';
import 'package:yhdm/bean/card/rule_card.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/widget/kazumi_menu.dart';
import 'package:yhdm/plugins/plugins.dart';
import 'package:yhdm/services/plugin/plugin_cookie_manager.dart';
import 'package:yhdm/services/plugin/plugin_login_check_service.dart';
import 'package:yhdm/pages/plugin_login/plugin_login_page.dart';
import 'package:yhdm/pages/plugin_editor/rule_settings_page.dart';
import 'package:yhdm/plugins/plugins_controller.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/navigation.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/pages/plugin_editor/plugin_update_actions.dart';
import 'package:yhdm/request/core/dio_factory.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/storage/settings_keys.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/utils/encoding.dart';
import 'package:yhdm/utils/http_headers.dart';
import 'package:yhdm/request/clients/plugin_site_client.dart';
import 'package:yhdm/request/apis/plugin_market_api.dart';
import 'package:file_picker/file_picker.dart';
import 'package:yhdm/services/plugin/plugin_import_parser.dart';
import 'package:yhdm/l10n/app_localizations.dart';

class PluginViewPage extends StatefulWidget {
  const PluginViewPage({
    super.key,
    required this.controller,
  });

  final PluginsController controller;

  @override
  State<PluginViewPage> createState() => _PluginViewPageState();
}

class _PluginViewPageState extends State<PluginViewPage>
    with SingleTickerProviderStateMixin {
  PluginsController get pluginsController => widget.controller;

  late TabController _tabController;

  // 是否处于多选模式
  bool isMultiSelectMode = false;

  // 已选中的规则名称集合
  final Set<String> selectedNames = {};

  // 当前选中的 tab
  int _currentTab = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

  /// 按关键词过滤后的规则列表（#7 规则搜索）
  List<Plugin> get _filteredPlugins {
    final list = _currentPlugins;
    if (_searchKeyword.isEmpty) return list;
    final kw = _searchKeyword.toLowerCase();
    return list
        .where((p) => p.name.toLowerCase().contains(kw))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTab = _tabController.index;
          // 切换 tab 时退出多选模式
          if (isMultiSelectMode) {
            isMultiSelectMode = false;
            selectedNames.clear();
          }
        });
      }
    });
    unawaited(_loadPluginUpdateStatus());
    // 🆕 规则更新红点：进入规则页即消费（清除入口角标）
    GStorage.putSetting(SettingsKeys.ruleUpdateCount, 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 获取当前 tab 的规则列表
  List<Plugin> get _currentPlugins {
    final all = pluginsController.pluginList;
    switch (_currentTab) {
      case 1: // XPath
        return all.where((p) => p.searchMode == 'xpath' || p.searchMode == 'api').toList();
      default: // 全部
        return List.from(all);
    }
  }

  Future<void> _handleUpdate() async {
    await updateAllPluginsWithFeedback(
      pluginsController,
      ensureCatalog: true,
    );
    if (mounted) setState(() {});
  }

  /// 🆕 检查登录状态：展示每条 needLogin 规则的真实过期时间与缓存情况，
  /// 并提供「重新登录 / 清除」操作。
  /// token 认证站点（有 check 配置）主动调用校验接口判断有效。
  Future<void> _showCookieStatusSheet(BuildContext context) async {
    final needLogin = pluginsController.pluginList
        .where((p) => p.needLogin)
        .toList();
    // 对有 check 配置的规则异步执行登录校验
    final checkResults = <String, bool>{};
    for (final p in needLogin.where((p) => p.usesApiCheck)) {
      final r = await PluginLoginCheckService.instance.check(p);
      checkResults[p.name] = r.valid;
    }
    if (!context.mounted) return;
    KazumiDialog.show(builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('登录状态检查'),
        content: SizedBox(
          width: 460,
          child: needLogin.isEmpty
              ? const Text('当前没有需要登录的规则')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in needLogin) ...[
                      _cookieStatusTile(ctx, p, checkResults),
                      if (p != needLogin.last)
                        Divider(color: cs.outlineVariant.withOpacity(0.4)),
                    ],
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: const Text('关闭'),
          ),
        ],
      );
    });
  }

  Widget _cookieStatusTile(
    BuildContext context,
    Plugin plugin,
    Map<String, bool> checkResults,
  ) {
    final cs = Theme.of(context).colorScheme;
    // token 认证站点（有 check 配置）：用 token 状态 + check 结果判断
    final isToken = plugin.usesApiCheck;
    final status = isToken
        ? {
            'hasCookie': PluginCookieManager.instance.hasToken(plugin.name),
            'valid': checkResults[plugin.name] == true,
            'expiresAt': PluginCookieManager.instance.tokenExpiresAt(plugin.name),
            'savedAt': null,
            'isSession': false,
            'cookieCount': PluginCookieManager.instance.hasToken(plugin.name) ? 1 : 0,
          }
        : PluginCookieManager.instance.cookieStatus(plugin.name);
    final hasCookie = status['hasCookie'] == true;
    final valid = status['valid'] == true;
    final expiresAt = status['expiresAt'] as DateTime?;
    final savedAt = status['savedAt'] as DateTime?;
    final isSession = status['isSession'] == true;
    final count = status['cookieCount'] as int? ?? 0;

    String fmt(DateTime? d) {
      if (d == null) return '—';
      final local = d.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${local.year}-${two(local.month)}-${two(local.day)} '
          '${two(local.hour)}:${two(local.minute)}';
    }

    final statusColor = !hasCookie
        ? cs.outline
        : valid
            ? Colors.green
            : cs.error;
    final statusText = !hasCookie
        ? '未登录 / 无缓存'
        : valid
            ? '有效'
            : '已过期';

    // 🆕 剩余有效期（token 规则）：显示「剩余 X 天/小时」徽章
    final remaining = expiresAt != null
        ? expiresAt.difference(DateTime.now())
        : null;
    String remainingText = '';
    Color remainingColor = cs.outline;
    if (isToken && expiresAt != null && remaining != null) {
      if (remaining.isNegative) {
        remainingText = '已过期';
        remainingColor = cs.error;
      } else if (remaining.inDays >= 1) {
        remainingText = '剩余 ${remaining.inDays} 天';
        remainingColor = Colors.green;
      } else if (remaining.inHours >= 1) {
        remainingText = '剩余 ${remaining.inHours} 小时';
        remainingColor = Colors.green;
      } else {
        remainingText = '剩余 ${remaining.inMinutes} 分钟';
        remainingColor = Colors.orange;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plugin.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(statusText,
                    style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 🆕 token 信息：已保存 / 过期时间 / 剩余，各占一行（避免过期时间被截断）
          if (isToken)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Token：${count > 0 ? '已保存' : '无'}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                if (expiresAt != null)
                  Text(
                    '过期 ${fmt(expiresAt)}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                if (remainingText.isNotEmpty)
                  Row(
                    children: [
                      Icon(
                        remainingText == '已过期'
                            ? Icons.timer_off_outlined
                            : Icons.timer_outlined,
                        size: 12,
                        color: remainingColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        remainingText,
                        style: TextStyle(
                          fontSize: 12,
                          color: remainingColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            )
          else
            Text(
              'Cookie：${count} 条 · 保存于 ${fmt(savedAt)}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          Text(
            isToken
                ? (plugin.checkConfig?.isLocal == true
                    ? '登录态由本地过期时间判定'
                    : '登录态由接口校验（check），非 Cookie 有效期')
                : isSession
                    ? '真实过期：该站未下发 expires（会话级）'
                    : '真实过期：${fmt(expiresAt)}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  KazumiDialog.dismiss();
                  final navContext = rootNavigatorKey.currentContext;
                  if (navContext == null || !navContext.mounted) return;
                  Navigator.of(navContext).push(
                    MaterialPageRoute(
                      builder: (_) => PluginLoginPage(plugin: plugin),
                    ),
                  );
                },
                icon: const Icon(Icons.login_rounded, size: 16),
                label: Text(valid ? '重新登录' : '去登录'),
              ),
              TextButton.icon(
                onPressed: hasCookie
                    ? () async {
                        await PluginCookieManager.instance.clear(plugin.name);
                        if (!context.mounted) return;
                        KazumiDialog.dismiss();
                        KazumiDialog.showToast(message: '已清除「${plugin.name}」登录缓存');
                      }
                    : null,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清除缓存'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleAdd() {
    KazumiDialog.show(builder: (context) {
      return AlertDialog(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_box),
                title: Text(AppLocalizations.of(context)!.setENewXPathRule),
                onTap: () {
                  KazumiDialog.dismiss();
                  context.pushNamed('/settings/plugin/editor',
                      arguments: Plugin.fromTemplate());
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.store),
                title: Text(AppLocalizations.of(context)!.setEImportFromRepo),
                onTap: () {
                  KazumiDialog.dismiss();
                  context.pushNamed('/settings/plugin/shop',
                      arguments: Plugin.fromTemplate());
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: Text(AppLocalizations.of(context)!.setEImportFromClipboard),
                onTap: () {
                  KazumiDialog.dismiss();
                  _showInputDialog();
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.file_open),
                title: Text(AppLocalizations.of(context)!.setEImportFromFile),
                onTap: () {
                  KazumiDialog.dismiss();
                  _importFromFile();
                },
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showInputDialog() {
    String pluginText = '';
    final controller = TextEditingController();
    var clipboardLoaded = false;
    KazumiDialog.show(
      builder: (context) {
        // 首次打开自动读取剪贴板填入，无需手动粘贴
        if (!clipboardLoaded) {
          clipboardLoaded = true;
          Clipboard.getData('text/plain').then((data) {
            final text = data?.text?.trim() ?? '';
            // 仅当剪贴板为 yhdmgz 链接或 HTTPS 链接时才自动粘贴，其他内容不自动填入
            final isAutoPaste =
                text.startsWith('yhdmgz://') || text.startsWith('https://');
            if (isAutoPaste) {
              pluginText = text;
              controller.text = text;
            }
          });
        }
        return AlertDialog(
          title: const Text('导入规则'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return TextField(
                controller: controller,
                onChanged: (value) => pluginText = value,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: '在这里粘贴规则链接或 JSON',
                  border: OutlineInputBorder(),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: Text('取消',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final plugin = Plugin.fromJson(
                    json.decode(kazumiBase64ToJson(pluginText)),
                  );
                  if (plugin.requiresNewerClient) {
                    KazumiDialog.dismiss();
                    KazumiDialog.showToast(message: '规则需要更高版本客户端');
                    return;
                  }
                  await pluginsController.updatePlugin(plugin);
                  KazumiDialog.dismiss();
                  KazumiDialog.showToast(message: '导入成功');
                } catch (e, st) {
                  KazumiLogger().e('导入失败', error: e, stackTrace: st);
                  KazumiDialog.dismiss();
                  KazumiDialog.showToast(message: '导入失败 ${e.toString()}');
                }
              },
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
  }

  // 官方 v2.3.0 新增：从文件批量导入规则
  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        throw const FileSystemException('无法读取所选文件');
      }
      await _importFromText(utf8.decode(bytes));
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'Plugin: failed to import rules from file',
        error: error,
        stackTrace: stackTrace,
      );
      KazumiDialog.showToast(message: '读取规则文件失败：$error');
    }
  }

  // 官方 v2.3.0 新增：批量解析并写入规则（支持多条 kazumi:// 或 JSON）
  Future<void> _importFromText(
    String text, {
    bool dismissDialog = false,
  }) async {
    final result = PluginImportParser.parse(text);
    if (result.plugins.isEmpty) {
      if (dismissDialog) KazumiDialog.dismiss();
      KazumiDialog.showToast(
        message: result.failures.isEmpty ? '没有可导入的规则' : result.failures.first,
      );
      return;
    }

    if (dismissDialog) KazumiDialog.dismiss();
    try {
      await pluginsController.updatePlugins(result.plugins);
      KazumiDialog.showToast(
        message: '导入完成：成功 ${result.plugins.length} 条，'
            '跳过重复 ${result.duplicateCount} 条，失败 ${result.failureCount} 条',
      );
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'Plugin: failed to persist imported rules',
        error: error,
        stackTrace: stackTrace,
      );
      KazumiDialog.showToast(message: '保存导入规则失败：$error');
    }
  }

  void onBackPressed(BuildContext context) {
    if (KazumiDialog.observer.hasKazumiDialog) {
      KazumiDialog.dismiss();
      return;
    }
  }

  Future<void> _loadPluginUpdateStatus() async {
    try {
      await pluginsController.ensurePluginCatalog();
      if (mounted) setState(() {});
    } catch (_) {
      // 静默失败
    }
  }

  Future<void> _selectAll() async {
    setState(() {
      selectedNames.addAll(_currentPlugins.map((p) => p.name));
    });
  }

  void _deleteSelected() {
    KazumiDialog.show(
      builder: (context) => AlertDialog(
        title: const Text('删除规则'),
        content: Text('确定要删除选中的 ${selectedNames.length} 条规则吗？'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: Text('取消',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          TextButton(
            onPressed: () async {
              try {
                await pluginsController.removePlugins(selectedNames);
              } catch (_) {
                KazumiDialog.showToast(message: '删除规则失败');
                return;
              }
              if (!mounted) return;
              setState(() {
                isMultiSelectMode = false;
                selectedNames.clear();
              });
              KazumiDialog.dismiss();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  /// #3 规则健康度检测：逐条测试搜索接口是否可达
  Future<void> _handleHealthCheck() async {
    final plugins = pluginsController.pluginList
        .where((p) => p.enabled && p.searchURL.isNotEmpty)
        .toList();
    if (plugins.isEmpty) {
      KazumiDialog.showToast(message: '没有可检测的启用规则');
      return;
    }
    KazumiDialog.showLoading(msg: '正在检测 ${plugins.length} 条规则...');
    final results = <String, bool>{};
    for (final p in plugins) {
      results[p.name] = await _testPlugin(p);
    }
    KazumiDialog.dismiss();
    if (!mounted) return;
    final okCount = results.values.where((v) => v).length;
    final bad = results.entries.where((e) => !e.value).toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('健康检测：$okCount/${results.length} 正常'),
        content: SizedBox(
          width: double.maxFinite,
          child: bad.isEmpty
              ? const Text('所有规则均正常 🎉')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('以下规则可能失效：', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final e in bad)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text('❌ ${e.key}',
                                    style: const TextStyle(color: Colors.red)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 单条规则检测：GET 搜索接口（占位符换测试词），检查可访问
  Future<bool> _testPlugin(Plugin p) async {
    try {
      final url = p.searchURL.replaceAll(
        '{keyword}',
        Uri.encodeComponent('进击的巨人'),
      );
      final response = await DioFactory.apiDio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          headers: {
            'user-agent': getRandomUA(),
            'referer': 'https://bgm.tv/',
          },
        ),
      );
      final body = response.data?.toString() ?? '';
      return response.statusCode == 200 && body.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !isMultiSelectMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isMultiSelectMode) {
          setState(() {
            isMultiSelectMode = false;
            selectedNames.clear();
          });
          return;
        }
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: SysAppBar(
          title: isMultiSelectMode
              ? Text('已选择 ${selectedNames.length} 项')
              : const Text('规则管理'),
          leading: isMultiSelectMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      isMultiSelectMode = false;
                      selectedNames.clear();
                    });
                  },
                )
              : null,
          actions: [
            if (isMultiSelectMode) ...[
              IconButton(
                onPressed: selectedNames.length < _currentPlugins.length
                    ? _selectAll
                    : null,
                icon: const Icon(Icons.select_all),
                tooltip: AppLocalizations.of(context)!.setESelectAll,
              ),
              IconButton(
                onPressed: selectedNames.isEmpty ? null : _deleteSelected,
                icon: const Icon(Icons.delete),
                tooltip: AppLocalizations.of(context)!.setEDeleteSelected,
              ),
            ] else ...[
              // 🆕 检查登录 Cookie 状态（真实过期时间）；仅当存在 needLogin 规则时显示
              if (pluginsController.pluginList.any((p) => p.needLogin))
                IconButton(
                  onPressed: () => _showCookieStatusSheet(context),
                  tooltip: '检查登录状态',
                  icon: const Icon(Icons.verified_user_outlined),
                ),
              // 收纳进「更多」菜单，右上角不再图标堆叠（AI生成器/规则设置/更新全部 全保留）
              PopupMenuButton<String>(
                tooltip: AppLocalizations.of(context)!.setEMore,
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  switch (v) {
                    case 'ai':
                      showMcpServerDialog(context);
                      break;
                    case 'settings':
                      final navContext = rootNavigatorKey.currentContext;
                      if (navContext == null || !navContext.mounted) break;
                      Navigator.of(navContext).push(
                        MaterialPageRoute(
                            builder: (_) => const RuleSettingsPage()),
                      );
                      break;
                    case 'update':
                      _handleUpdate();
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'ai',
                    child: ListTile(
                      leading: Icon(Icons.smart_toy_rounded),
                      title: Text(AppLocalizations.of(ctx)!.setEAIRuleGenerator),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      leading: Icon(Icons.tune_rounded),
                      title: Text(AppLocalizations.of(ctx)!.setERuleSettings),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'update',
                    child: ListTile(
                      leading: Icon(Icons.update),
                      title: Text(AppLocalizations.of(ctx)!.setEUpdateAll),
                    ),
                  ),
                ],
              ),
              IconButton(
                key: TutorialKeys.ruleAdd,
                onPressed: _handleAdd,
                tooltip: AppLocalizations.of(context)!.setEAddRule,
                icon: const Icon(Icons.add),
              ),
            ],
          ],
          bottom: isMultiSelectMode
              ? null
              : TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: AppLocalizations.of(context)!.setETabAll),
                    Tab(text: 'XPath'),
                  ],
                ),
        ),
        body: isMultiSelectMode
            ? _buildRuleList(_filteredPlugins, colorScheme)
            : Column(
                children: [
                  // 🆕 规则更新提示条（目录加载后有可更新规则时显示）
                  _buildUpdateBanner(colorScheme),
                  // #7 规则搜索框
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchKeyword = v.trim()),
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!.setESearchRuleHint,
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchKeyword.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchKeyword = '');
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRuleList(_filteredPlugins, colorScheme),
                        _buildRuleList(_filteredPlugins, colorScheme),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildUpdateBanner(ColorScheme colorScheme) {
    final updatable = pluginsController.pluginList
        .where((p) =>
            pluginsController.pluginUpdateStatus(p) ==
            PluginUpdateAvailability.updatable)
        .length;
    if (updatable == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.system_update_alt_rounded,
                  size: 20, color: colorScheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '有 $updatable 个规则可以更新',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _handleUpdate,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('全部更新'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRuleList(List<Plugin> plugins, ColorScheme colorScheme) {
    if (plugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_off, size: 64, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              _currentTab == 1
                  ? '没有 XPath 规则'
                  : '啊咧（⊙.⊙） 没有可用规则的说',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        final bool canUpdate =
            pluginsController.pluginUpdateStatus(plugin) ==
                PluginUpdateAvailability.updatable;

        final tags = <Widget>[
          RuleTag(
            label: plugin.version,
            background: colorScheme.secondaryContainer,
            foreground: colorScheme.onSecondaryContainer,
          ),
          if (plugin.searchMode == 'css')
            RuleTag(
              label: 'CSS',
              background: colorScheme.tertiaryContainer,
              foreground: colorScheme.onTertiaryContainer,
            ),
          if (plugin.searchMode == 'rss')
            RuleTag(
              label: 'RSS',
              background: colorScheme.primaryContainer,
              foreground: colorScheme.onPrimaryContainer,
            ),
          if (canUpdate)
            RuleTag(
              label: AppLocalizations.of(context)!.setEUpdatable,
              background: colorScheme.errorContainer,
              foreground: colorScheme.onErrorContainer,
            ),
          if (pluginsController.validityTracker
              .isSearchValid(plugin.name))
            RuleTag(
              label: AppLocalizations.of(context)!.setESearchValid,
              background: colorScheme.tertiaryContainer,
              foreground: colorScheme.onTertiaryContainer,
            ),
          // 🆕 需登录的规则（如次元城）：紫色标签提示，与选源面板的紫色状态一致
          if (plugin.needLogin)
            const RuleTag(
              label: '需登录',
              background: Color(0xFFF3E8FF),
              foreground: Color(0xFF7B3FF2),
            ),
        ];

        final VoidCallback? onTap;
        onTap = () {
          if (isMultiSelectMode) {
            _toggleSelect(plugin);
          }
        };

        final String? caption = null;

        return Dismissible(
          key: ObjectKey(plugin),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            if (!context.mounted) return false;
            await context.pushNamed('/settings/plugin/editor',
                arguments: plugin);
            if (context.mounted) setState(() {});
            return false;
          },
          background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, color: colorScheme.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Text('编辑',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          )),
                    ],
                  ),
                ),
          child: RuleCard(
            key: ObjectKey(plugin),
            title: plugin.name,
            selected: selectedNames.contains(plugin.name),
            iconUrl: plugin.icon.isNotEmpty ? plugin.icon : null,
            caption: caption,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    icon: Icon(
                      plugin.enabled
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: plugin.enabled
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                    onPressed: () {
                      setState(() {
                        plugin.enabled = !plugin.enabled;
                      });
                      unawaited(pluginsController.updatePlugin(plugin));
                    },
                    tooltip: plugin.enabled ? '点击禁用' : '点击启用',
                  ),
                ),
                if (!isMultiSelectMode) _popupMenuButton(plugin),
              ],
            ),
            onLongPress: () {
              if (!isMultiSelectMode) {
                setState(() {
                  isMultiSelectMode = true;
                  selectedNames.add(plugin.name);
                });
              }
            },
            onTap: onTap,
            tags: tags,
          ),
        );
      },
    );
  }

  void _toggleSelect(Plugin plugin) {
    setState(() {
      if (selectedNames.contains(plugin.name)) {
        selectedNames.remove(plugin.name);
        if (selectedNames.isEmpty) {
          isMultiSelectMode = false;
        }
      } else {
        selectedNames.add(plugin.name);
      }
    });
  }

  Widget _popupMenuButton(Plugin plugin) {
    return KazumiMenuButton(
      builder: (context, toggle) => IconButton(
        onPressed: toggle,
        icon: const Icon(Icons.more_vert),
      ),
      menuChildren: [
        KazumiMenuItem(
          onPressed: () async {
            final l10n = AppLocalizations.of(context)!;
            try {
              await pluginsController.ensurePluginCatalog();
              if (mounted) setState(() {});
            } catch (_) {
              KazumiDialog.showToast(message: '检查规则更新失败');
              return;
            }
            final state = pluginsController.pluginUpdateStatus(plugin);
            switch (state) {
              case PluginUpdateAvailability.unknown:
                KazumiDialog.showToast(message: l10n.setENoUpdateStatus);
              case PluginUpdateAvailability.notInCatalog:
                KazumiDialog.showToast(message: l10n.setENotInCatalog);
              case PluginUpdateAvailability.latest:
                KazumiDialog.showToast(message: l10n.setEAlreadyLatest);
              case PluginUpdateAvailability.updatable:
                await updatePluginWithFeedback(
                    pluginsController, plugin.name, installing: false);
            }
          },
          label: AppLocalizations.of(context)!.setEUpdate,
          leadingIcon: Icon(Icons.update_rounded),
        ),
        KazumiMenuItem(
          onPressed: () {
            context.pushNamed('/settings/plugin/editor', arguments: plugin);
          },
          label: AppLocalizations.of(context)!.setCEdit,
          leadingIcon: Icon(Icons.edit),
        ),
        KazumiMenuItem(
          onPressed: () {
            context.pushNamed('/settings/plugin/test', arguments: plugin);
          },
          label: '测试',
          leadingIcon: Icon(Icons.bug_report_outlined),
        ),
        if (PluginCookieManager.instance.hasSaved(plugin.name))
          KazumiMenuItem(
            onPressed: () async {
              await PluginCookieManager.instance.clear(plugin.name);
              if (mounted) setState(() {});
              KazumiDialog.showToast(
                  message: '已清除「${plugin.name}」的登录态(Cookie)，下次播放会重新要求登录');
            },
            label: '清除 Cookie',
          leadingIcon: Icon(Icons.cookie_outlined),
          ),
        KazumiMenuItem(
          onPressed: () {
            final pluginJson = json.encode(plugin.toJson());
            final httpLink = jsonToShareUrl(pluginJson);
            final yhdmgzLink = jsonToKazumiBase64(pluginJson);
            KazumiDialog.show(builder: (context) {
              return AlertDialog(
                title: const Text('分享规则'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.link),
                      title: const Text('HTTP 链接（可分享给好友）'),
                      subtitle: Text(httpLink, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: httpLink));
                        KazumiDialog.dismiss();
                        KazumiDialog.showToast(message: '已复制 HTTP 链接');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.shield),
                      title: const Text('yhdmgz 协议链接（App内使用）'),
                      subtitle: Text(yhdmgzLink, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: yhdmgzLink));
                        KazumiDialog.dismiss();
                        KazumiDialog.showToast(message: '已复制 yhdmgz 链接');
                      },
                    ),
                    // 🆕 分享已移除「分享给好友」（App 内好友功能已下线）
                  ],
                ),
              );
            });
          },
          label: AppLocalizations.of(context)!.setEShare,
          leadingIcon: Icon(Icons.share),
        ),
        KazumiMenuItem(
          onPressed: () async {
            final pluginJson = json.encode(plugin.toJson());
            // 上传前确认 + 选择来源站分类
            String? selectedCategory = '其他';
            final categoryInput = TextEditingController();
            final confirm = await KazumiDialog.show<String>(
              builder: (context) => StatefulBuilder(
                builder: (context, setState) => AlertDialog(
                  title: const Text('上传到规则市场'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '将规则「${plugin.name}」上传到公开规则市场\n'
                        '(qlyyz.xyz/json/)\n\n'
                        '任何人都可以看到并安装它。\n\n'
                        '选择来源站分类：',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in ['樱花', '樱花动漫', '其他'])
                            ChoiceChip(
                              label: Text(c),
                              selected: selectedCategory == c,
                              onSelected: (_) {
                                setState(() {
                                  selectedCategory = c;
                                  categoryInput.clear();
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: categoryInput,
                        decoration: const InputDecoration(
                          labelText: '或自定义来源站',
                          hintText: '留空则使用上面选择的分类',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          if (v.trim().isNotEmpty) {
                            selectedCategory = v.trim();
                          }
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => KazumiDialog.dismiss(popWith: null),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          KazumiDialog.dismiss(popWith: selectedCategory),
                      child: const Text('上传'),
                    ),
                  ],
                ),
              ),
            );
            if (confirm == null) return;
            categoryInput.dispose();
            KazumiDialog.showToast(message: '正在上传…');
            final result = await PluginMarketApi.uploadRule(
              name: plugin.name,
              content: pluginJson,
              category: confirm,
            );
            if (mounted) {
              KazumiDialog.showToast(message: result);
            }
          },
          label: AppLocalizations.of(context)!.setEUploadToMarket,
          leadingIcon: Icon(Icons.cloud_upload_outlined),
        ),
        KazumiMenuItem(
          onPressed: () async {
            try {
              await pluginsController.removePlugin(plugin);
              if (mounted) setState(() {});
            } catch (_) {
              KazumiDialog.showToast(message: '删除规则失败');
            }
          },
          label: '删除',
          leadingIcon: Icon(Icons.delete),
        ),
      ],
    );
  }

}

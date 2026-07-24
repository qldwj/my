import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/animeko_converter.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/pages/plugin_editor/plugin_update_actions.dart';
import 'package:kazumi/pages/plugin_editor/collection_browser_page.dart';
import 'package:kazumi/pages/plugin_editor/collection_detail_page.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/encoding.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';

/// 默认 Animeko 规则仓库地址
const String kAnimekoRepoBase = 'https://raw.githubusercontent.com/qlgfwz/anisubs/main/';
const String kAnimekoRepoIndex = kAnimekoRepoBase + 'main.json';

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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 获取当前 tab 的规则列表
  List<Plugin> get _currentPlugins {
    final all = pluginsController.pluginList;
    switch (_currentTab) {
      case 1: // XPath
        return all.where((p) => p.searchMode == 'xpath' || p.searchMode == 'api').toList();
      case 2: // Animeko — 只显示合集
        return all.where((p) => p.isCollection).toList();
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

  void _handleAdd() {
    KazumiDialog.show(builder: (context) {
      return AlertDialog(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_download),
                title: const Text('从仓库安装合集'),
                subtitle: const Text('浏览并安装 Animeko 合集'),
                onTap: () {
                  KazumiDialog.dismiss();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CollectionBrowserPage(
                        controller: pluginsController,
                      ),
                    ),
                  ).then((changed) {
                    if (changed == true && mounted) setState(() {});
                  });
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.add_box),
                title: const Text('新建 XPath 规则'),
                onTap: () {
                  KazumiDialog.dismiss();
                  context.pushNamed('/settings/plugin/editor',
                      arguments: Plugin.fromTemplate());
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.store),
                title: const Text('从规则仓库导入'),
                onTap: () {
                  KazumiDialog.dismiss();
                  context.pushNamed('/settings/plugin/shop',
                      arguments: Plugin.fromTemplate());
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: const Text('从剪贴板导入'),
                onTap: () {
                  KazumiDialog.dismiss();
                  _showInputDialog();
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.extension),
                title: const Text('导入 Animeko JSON'),
                subtitle: const Text('从链接或剪贴板导入单个规则'),
                onTap: () {
                  KazumiDialog.dismiss();
                  _showAnimekoImportDialog();
                },
              ),
            ],
          ),
        ),
      );
    });
  }

  /// 从默认 Animeko 仓库导入/更新所有规则
  Future<int> _importFromAnimekoRepo() async {
    KazumiDialog.showLoading(msg: '正在从仓库获取规则...');
    String? errorDetail;
    try {
      // 1. 获取 main.json 索引
      String indexJson;
      try {
        indexJson = await PluginSiteClient.instance.requestText(
          kAnimekoRepoIndex,
          method: 'GET',
        );
      } catch (e) {
        errorDetail = '无法访问仓库: $e';
        KazumiLogger().e('AnimekoRepo: 获取索引失败', error: e);
        KazumiDialog.dismiss();
        KazumiDialog.showToast(message: errorDetail!);
        return -1;
      }

      if (indexJson.trim().isEmpty) {
        KazumiDialog.dismiss();
        KazumiDialog.showToast(message: '仓库返回空内容');
        return -1;
      }

      late final dynamic indexData;
      try {
        indexData = jsonDecode(indexJson);
      } catch (e) {
        KazumiDialog.dismiss();
        KazumiDialog.showToast(message: '仓库索引格式错误: $e');
        return -1;
      }
      
      // 解析索引文件（支持两种格式：数组 或 { "rules": [...] }）
      List<dynamic> ruleEntries;
      if (indexData is List) {
        ruleEntries = indexData;
      } else if (indexData is Map && indexData['rules'] is List) {
        ruleEntries = indexData['rules'] as List<dynamic>;
      } else {
        KazumiDialog.dismiss();
        KazumiDialog.showToast(message: '仓库索引格式无法识别，请检查 main.json 格式');
        return -1;
      }

      if (ruleEntries.isEmpty) {
        KazumiDialog.dismiss();
        KazumiDialog.showToast(message: '仓库中没有规则');
        return 0;
      }

      // 2. 逐个下载规则
      int successCount = 0;
      int failCount = 0;
      String lastError = '';

      // 更新加载提示
      KazumiDialog.showLoading(msg: '找到 ${ruleEntries.length} 个规则，正在下载...');

      for (final entry in ruleEntries) {
        String ruleUrl;
        String ruleName;

        if (entry is String) {
          ruleUrl = entry;
          ruleName = entry.replaceAll('.json', '').replaceAll(RegExp(r'^[\/]+'), '');
        } else if (entry is Map) {
          ruleUrl = (entry['file'] ?? entry['url'] ?? '').toString();
          ruleName = (entry['name'] ?? ruleUrl.replaceAll('.json', '')).toString();
        } else {
          continue;
        }

        if (ruleUrl.isEmpty) continue;

        // 构建完整 URL
        final fullUrl = ruleUrl.startsWith('http') ? ruleUrl : kAnimekoRepoBase + ruleUrl;
        
        try {
          final ruleJson = await PluginSiteClient.instance.requestText(
            fullUrl,
            method: 'GET',
          );
          
          if (ruleJson.trim().isEmpty) {
            lastError = '$ruleName 返回空';
            failCount++;
            continue;
          }

          final plugins = AnimekoRuleConverter.convertFromJson(ruleJson);
          
          if (plugins.isEmpty) {
            lastError = '$ruleName 未解析到规则';
            failCount++;
            continue;
          }

          for (final plugin in plugins) {
            // 检查是否已存在同名规则 → 替换
            bool replaced = false;
            for (int i = 0; i < pluginsController.pluginList.length; i++) {
              if (pluginsController.pluginList[i].name == plugin.name) {
                pluginsController.pluginList[i] = plugin;
                replaced = true;
                break;
              }
            }
            if (!replaced) {
              pluginsController.pluginList.add(plugin);
            }
          }
          successCount += plugins.length;
        } catch (e) {
          lastError = '$ruleName: $e';
          KazumiLogger().w('AnimekoRepo: 下载规则 $ruleName 失败: $e');
          failCount++;
        }
      }

      await pluginsController.savePlugins();
      KazumiDialog.dismiss();

      // 显示详细结果
      final msg = failCount > 0
          ? '成功导入 $successCount 条，失败 $failCount 条'
          : '成功导入 $successCount 条规则';
      KazumiDialog.showToast(message: msg);
      if (failCount > 0) {
        KazumiLogger().w('AnimekoRepo: $failCount 个规则下载失败。最后错误: $lastError');
      }
      return successCount;
    } catch (e, st) {
      KazumiLogger().e('AnimekoRepo: 导入失败', error: e, stackTrace: st);
      KazumiDialog.dismiss();
      KazumiDialog.showToast(message: '导入失败: ${e.toString()}');
      return -1;
    }
  }

  /// 从 JSON 内容或链接创建合集
  Future<void> _createCollectionFromJson(String jsonStr, String name) async {
    final plugins = AnimekoRuleConverter.convertFromJson(jsonStr);
    if (plugins.isEmpty) return;

    final now = _formatTime(DateTime.now());
    final next = _formatTime(DateTime.now().add(_getUpdateInterval()));

    // 去重：如果已存在的合集或规则中有同名的子规则，跳过
    final existingNames = <String>{};
    for (final existing in pluginsController.pluginList) {
      if (existing.isCollection) {
        for (final child in existing.childPlugins) {
          existingNames.add(child.name);
        }
      } else {
        existingNames.add(existing.name);
      }
    }
    final uniquePlugins = <Plugin>[];
    for (final p in plugins) {
      if (!existingNames.contains(p.name)) {
        uniquePlugins.add(p);
        existingNames.add(p.name);
      }
    }

    if (uniquePlugins.isEmpty) {
      KazumiDialog.showToast(message: '所有规则已存在，无需重复添加');
      return;
    }

    final collection = Plugin(
      api: '5',
      type: 'anime',
      name: name,
      version: '1.0',
      muliSources: true,
      useWebview: true,
      useNativePlayer: true,
      usePost: false,
      useLegacyParser: false,
      adBlocker: true,
      userAgent: '',
      baseUrl: '',
      searchURL: '',
      searchList: '',
      searchName: '',
      searchResult: '',
      chapterRoads: '',
      chapterResult: '',
      referer: '',
      searchMode: 'css',
      chapterMode: 'css',
      enabled: true,
      isCollection: true,
      collectionUrl: '',
      collectionLastUpdate: now,
      collectionNextUpdate: next,
      childPlugins: uniquePlugins,
    );

    bool replaced = false;
    for (int i = 0; i < pluginsController.pluginList.length; i++) {
      if (pluginsController.pluginList[i].name == collection.name) {
        pluginsController.pluginList[i] = collection;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      pluginsController.pluginList.add(collection);
    }
    await pluginsController.savePlugins();
    KazumiDialog.showToast(
      message: '合集已添加 (${uniquePlugins.length} 条规则)',
    );
  }

  void _showAnimekoImportDialog() {
    String inputText = '';
    String nameText = '';
    final isUrl = ValueNotifier<bool>(false);

    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          title: const Text('导入 Animeko 合集'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '输入 JSON 链接 或 粘贴 JSON 内容，将创建为一个合集',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: '合集名称',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => nameText = v,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'https://example.com/rules.json\n'
                          '或直接粘贴规则 JSON',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      inputText = value;
                      isUrl.value = value.trim().startsWith('http');
                    },
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: isUrl,
                    builder: (context, urlMode, _) {
                      return Row(
                        children: [
                          Icon(
                            urlMode ? Icons.link : Icons.data_object,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            urlMode ? '将作为链接获取' : '将作为 JSON 解析',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      );
                    },
                  ),
                ],
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
                final text = inputText.trim();
                if (text.isEmpty) return;
                final collName = nameText.trim().isEmpty ? '导入合集' : nameText.trim();
                KazumiDialog.showLoading(msg: '处理中...');
                try {
                  String jsonStr;
                  if (text.startsWith('http')) {
                    jsonStr = await PluginSiteClient.instance.requestText(
                      text,
                      method: 'GET',
                    );
                  } else {
                    jsonStr = text;
                  }
                  await _createCollectionFromJson(jsonStr, collName);
                  KazumiDialog.dismiss();
                  if (mounted) setState(() {});
                  KazumiDialog.showToast(message: '合集 "$collName" 导入成功');
                } catch (e, st) {
                  KazumiLogger().e('导入合集失败', error: e, stackTrace: st);
                  KazumiDialog.dismiss();
                  KazumiDialog.showToast(message: '导入失败: ${e.toString()}');
                }
              },
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }
  String _pad(int n) => n.toString().padLeft(2, '0');

  Duration _getUpdateInterval() {
    final minutes = GStorage.getSetting(SettingsKeys.animekoUpdateInterval);
    return Duration(minutes: minutes > 0 ? minutes : 30);
  }

  void _showInputDialog() {
    String pluginText = '';
    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          title: const Text('导入规则'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return TextField(
                onChanged: (value) => pluginText = value,
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
                tooltip: '全选',
              ),
              IconButton(
                onPressed: selectedNames.isEmpty ? null : _deleteSelected,
                icon: const Icon(Icons.delete),
                tooltip: '删除选中',
              ),
            ] else ...[
              IconButton(
                onPressed: _handleUpdate,
                tooltip: '更新全部',
                icon: const Icon(Icons.update),
              ),
              IconButton(
                onPressed: _handleAdd,
                tooltip: '添加规则',
                icon: const Icon(Icons.add),
              ),
            ],
          ],
          bottom: isMultiSelectMode
              ? null
              : TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: '全部'),
                    Tab(text: 'XPath'),
                    Tab(text: 'Animeko'),
                  ],
                ),
        ),
        body: isMultiSelectMode
            ? _buildRuleList(_currentPlugins, colorScheme)
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildRuleList(_currentPlugins, colorScheme),
                  _buildRuleList(_currentPlugins, colorScheme),
                  _buildRuleList(_currentPlugins, colorScheme),
                ],
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
                  : _currentTab == 2
                      ? '没有 Animeko 规则'
                      : '啊咧（⊙.⊙） 没有可用规则的说',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (_currentTab == 2) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline,
                      size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '点击右上角 ＋ → 从仓库安装合集',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
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
          if (plugin.isCollection)
            RuleTag(
              label: '合集',
              background: colorScheme.primaryContainer,
              foreground: colorScheme.onPrimaryContainer,
            ),
          if (!plugin.isCollection && plugin.searchMode == 'css')
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
              label: '可更新',
              background: colorScheme.errorContainer,
              foreground: colorScheme.onErrorContainer,
            ),
          if (pluginsController.validityTracker
              .isSearchValid(plugin.name))
            RuleTag(
              label: '搜索有效',
              background: colorScheme.tertiaryContainer,
              foreground: colorScheme.onTertiaryContainer,
            ),
        ];

        // 合集卡片点击 → 打开合集详情
        final VoidCallback? onTap;
        if (plugin.isCollection) {
          onTap = () {
            if (isMultiSelectMode) {
              _toggleSelect(plugin);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CollectionDetailPage(plugin: plugin),
                ),
              );
            }
          };
        } else {
          onTap = () {
            if (isMultiSelectMode) {
              _toggleSelect(plugin);
            }
          };
        }

        // 合集显示更新信息
        final String? caption;
        if (plugin.isCollection && plugin.collectionLastUpdate.isNotEmpty) {
          caption =
              '上次: ${plugin.collectionLastUpdate}  下次: ${plugin.collectionNextUpdate}';
        } else {
          caption = null;
        }

        return Dismissible(
          key: ObjectKey(plugin),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            if (!context.mounted) return false;
            if (plugin.isCollection) {
              // 合集不能编辑
              return false;
            }
            await context.pushNamed('/settings/plugin/editor',
                arguments: plugin);
            if (context.mounted) setState(() {});
            return false;
          },
          background: plugin.isCollection
              ? Container()
              : Container(
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
    return MenuAnchor(
      consumeOutsideTap: true,
      builder: (BuildContext context, MenuController controller, Widget? child) {
        return IconButton(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: const Icon(Icons.more_vert),
        );
      },
      menuChildren: [
        MenuItemButton(
          onPressed: () async {
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
                KazumiDialog.showToast(message: '尚未获取规则更新状态');
              case PluginUpdateAvailability.notInCatalog:
                KazumiDialog.showToast(message: '规则仓库中没有当前规则');
              case PluginUpdateAvailability.latest:
                KazumiDialog.showToast(message: '规则已是最新');
              case PluginUpdateAvailability.updatable:
                await updatePluginWithFeedback(
                    pluginsController, plugin.name, installing: false);
            }
          },
          child: _menuItem(Icons.update_rounded, '更新'),
        ),
        MenuItemButton(
          onPressed: () {
            context.pushNamed('/settings/plugin/editor', arguments: plugin);
          },
          child: _menuItem(Icons.edit, '编辑'),
        ),
        MenuItemButton(
          onPressed: () {
            context.pushNamed('/settings/plugin/test', arguments: plugin);
          },
          child: _menuItem(Icons.bug_report_outlined, '测试'),
        ),
        MenuItemButton(
          onPressed: () {
            KazumiDialog.show(builder: (context) {
              return AlertDialog(
                title: const Text('规则链接'),
                content: SelectableText(
                  jsonToKazumiBase64(json.encode(plugin.toJson())),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                actions: [
                  TextButton(
                    onPressed: () => KazumiDialog.dismiss(),
                    child: Text('取消',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline)),
                  ),
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                        text: jsonToKazumiBase64(json.encode(plugin.toJson())),
                      ));
                      KazumiDialog.dismiss();
                    },
                    child: const Text('复制到剪贴板'),
                  ),
                ],
              );
            });
          },
          child: _menuItem(Icons.share, '分享'),
        ),
        MenuItemButton(
          onPressed: () async {
            try {
              await pluginsController.removePlugin(plugin);
              if (mounted) setState(() {});
            } catch (_) {
              KazumiDialog.showToast(message: '删除规则失败');
            }
          },
          child: _menuItem(Icons.delete, '删除'),
        ),
      ],
    );
  }

  Widget _menuItem(IconData icon, String label) {
    return Container(
      height: 48,
      constraints: const BoxConstraints(minWidth: 112),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
            children: [Icon(icon), const SizedBox(width: 8), Text(label)]),
      ),
    );
  }
}

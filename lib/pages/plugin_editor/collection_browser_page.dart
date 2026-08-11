import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/animeko_converter.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';

/// 仓库索引中的一条记录
class _RepoEntry {
  final String name;
  final String file;
  _RepoEntry(this.name, this.file);
}

/// 合集浏览器页面
///
/// 从仓库获取可用合集列表，用户选择安装。
class CollectionBrowserPage extends StatefulWidget {
  const CollectionBrowserPage({super.key, required this.controller});

  final PluginsController controller;

  @override
  State<CollectionBrowserPage> createState() => _CollectionBrowserPageState();
}

class _CollectionBrowserPageState extends State<CollectionBrowserPage> {
  PluginsController get pluginsController => widget.controller;

  static const String repoBase =
      'https://raw.githubusercontent.com/qlgfwz/anisubs/main/';
  static const String repoIndex = repoBase + 'main.json';

  List<_RepoEntry> _entries = [];
  Set<int> _selected = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await PluginSiteClient.instance.requestText(
        repoIndex,
        method: 'GET',
      );
      final data = jsonDecode(json);

      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['rules'] is List) {
        list = data['rules'] as List<dynamic>;
      } else {
        setState(() {
          _error = 'main.json 格式无法识别';
          _loading = false;
        });
        return;
      }

      final entries = <_RepoEntry>[];
      for (final item in list) {
        if (item is String) {
          entries.add(_RepoEntry(
            item.replaceAll('.json', '').replaceAll(RegExp(r'^[/]+'), ''),
            item,
          ));
        } else if (item is Map) {
          final file = (item['file'] ?? item['url'] ?? '').toString();
          final name = (item['name'] ?? file.replaceAll('.json', '')).toString();
          if (file.isNotEmpty) {
            entries.add(_RepoEntry(name, file));
          }
        }
      }

      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e, st) {
      KazumiLogger().e('合集仓库加载失败', error: e, stackTrace: st);
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  Future<void> _installSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    KazumiDialog.showLoading(msg: '正在安装 $count 个合集...');

    int success = 0;
    int fail = 0;
    for (final index in _selected) {
      final entry = _entries[index];
      final url = entry.file.startsWith('http') ? entry.file : repoBase + entry.file;
      try {
        final json = await PluginSiteClient.instance.requestText(
          url,
          method: 'GET',
        );
        final plugins = AnimekoRuleConverter.convertFromJson(json);

        // 创建合集插件
        final collection = Plugin(
          api: '5',
          type: 'anime',
          name: entry.name,
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
          collectionUrl: url,
          collectionLastUpdate: _formatNow(),
          collectionNextUpdate: _formatNext(),
          childPlugins: plugins,
        );

        // 替换或添加
        bool replaced = false;
        for (int i = 0; i < pluginsController.pluginList.length; i++) {
          if (pluginsController.pluginList[i].name == entry.name) {
            pluginsController.pluginList[i] = collection;
            replaced = true;
            break;
          }
        }
        if (!replaced) {
          pluginsController.pluginList.add(collection);
        }
        success++;
      } catch (e) {
        KazumiLogger().w('安装合集 ${entry.name} 失败: $e');
        fail++;
      }
    }

    await pluginsController.savePlugins();

    if (mounted) {
      KazumiDialog.dismiss();
      KazumiDialog.showToast(message: '安装完成: 成功 $success, 失败 $fail');
      Navigator.of(context).pop(true); // 返回并标记有更新
    }
  }

  String _formatNow() {
    final now = DateTime.now();
    return '${now.year}-${_pad(now.month)}-${_pad(now.day)} ${_pad(now.hour)}:${_pad(now.minute)}';
  }

  String _formatNext() {
    final next = DateTime.now().add(const Duration(minutes: 60));
    return '${next.year}-${_pad(next.month)}-${_pad(next.day)} ${_pad(next.hour)}:${_pad(next.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(
        title: Text('安装合集  (${_selected.length})'),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _installSelected,
              child: const Text('安装'),
            ),
        ],
      ),
      body: _buildBody(colorScheme),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadIndex,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('仓库中没有可用合集'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final selected = _selected.contains(index);
        return RuleCard(
          title: entry.name,
          selected: selected,
          trailing: Checkbox(
            value: selected,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selected.add(index);
                } else {
                  _selected.remove(index);
                }
              });
            },
          ),
          onTap: () {
            setState(() {
              if (selected) {
                _selected.remove(index);
              } else {
                _selected.add(index);
              }
            });
          },
          onLongPress: () {
            setState(() {
              if (_selected.length == _entries.length) {
                _selected.clear();
              } else {
                _selected.addAll(List.generate(_entries.length, (i) => i));
              }
            });
          },
        );
      },
    );
  }
}

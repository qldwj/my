import 'package:yhdm/modules/search/plugin_search_module.dart';
import 'package:yhdm/pages/info/info_controller.dart';
import 'package:yhdm/plugins/plugins.dart';
import 'package:yhdm/plugins/plugins_controller.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/plugin/rule_engine_models.dart';
import 'package:yhdm/utils/async_session.dart';

class PluginSearchService {
  PluginSearchService({
    required this.infoController,
    required this.pluginsController,
  });

  final InfoController infoController;
  final PluginsController pluginsController;
  final RuleCancelToken _cancelToken = RuleCancelToken();

  /// Per-plugin sessions so a replacement query (alias/manual search)
  /// invalidates the write-back of the still-running previous one.
  final Map<String, AsyncSessionOwner> _querySessions = {};
  bool _isCancelled = false;

  Future<void> querySource(String keyword, String pluginName) async {
    // 先在主列表中查找
    for (final plugin in pluginsController.pluginList) {
      if (plugin.name == pluginName && plugin.enabled) {
        infoController.pluginSearchResponseList.removeWhere(
          (response) => response.pluginName == pluginName,
        );
        infoController.pluginSearchStatus[pluginName] =
            PluginSearchStatus.pending;
        await _queryPlugin(plugin, keyword);
        return;
      }
    }
    // 再在合集的子规则中查找
    for (final p in pluginsController.pluginList) {
      if (p.isCollection) {
        for (final child in p.childPlugins) {
          if (child.name == pluginName && child.enabled) {
            infoController.pluginSearchResponseList.removeWhere(
              (response) => response.pluginName == pluginName,
            );
            infoController.pluginSearchStatus[pluginName] =
                PluginSearchStatus.pending;
            await _queryPlugin(child, keyword);
            return;
          }
        }
      }
    }
  }

  /// 获取所有需要搜索的插件（合集展开为子规则）
  List<Plugin> _getSearchablePlugins() {
    final result = <Plugin>[];
    for (final p in pluginsController.pluginList) {
      if (!p.enabled) continue;
      if (p.isCollection) {
        // 合集展开为子规则进行搜索
        for (final child in p.childPlugins) {
          if (child.enabled && child.searchURL.isNotEmpty) {
            result.add(child);
          }
        }
      } else {
        result.add(p);
      }
    }
    return result;
  }

  Future<void> queryAllSource(String keyword) async {
    infoController.pluginSearchResponseList.clear();
    infoController.pluginSearchStatus.clear();

    final plugins = _getSearchablePlugins();
    for (final plugin in plugins) {
      infoController.pluginSearchStatus[plugin.name] =
          PluginSearchStatus.pending;
    }
    // 🔴 修复：规则多时全量并发会把站点/本地连接打爆导致大量失败，
    // 改为受限并发（同时最多 5 个），其余排队，大幅降低加载失败率。
    const maxConcurrent = 5;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= plugins.length) return;
        await _queryPlugin(plugins[i], keyword);
      }
    }
    await Future.wait(
      List.generate(maxConcurrent.clamp(1, plugins.length), (_) => worker()),
    );
  }

  Future<void> _queryPlugin(Plugin plugin, String keyword) async {
    if (_isCancelled) return;
    // ⚠️ needLogin 只代表「播放/解析章节需要登录」，很多站点（如次元城）的
    // 搜索接口本身并不需要登录。这里不能因为未登录就跳过搜索，否则源会从列表
    // 直接消失，用户会以为「这个源不能用」。照常搜索，真正需要登录的环节
    // （如 API 返回未授权）会自然地失败并在下方 catch 中体现。
    final session = _querySessions
        .putIfAbsent(plugin.name, AsyncSessionOwner.new)
        .begin();
    try {
      final result = await plugin.queryBangumi(
        keyword,
        shouldRethrow: true,
        cancelToken: _cancelToken,
      );
      if (_isCancelled || session.isStale) return;
      infoController.pluginSearchStatus[plugin.name] =
          PluginSearchStatus.success;
      if (result.data.isNotEmpty) {
        pluginsController.validityTracker.markSearchValid(plugin.name);
      }
      infoController.pluginSearchResponseList.add(result);
    } catch (error) {
      if (_isCancelled || session.isStale) return;
      _handleSearchError(plugin, error);
    }
  }

  void _handleSearchError(Plugin plugin, Object error) {
    if (error is CaptchaRequiredException) {
      KazumiLogger().i(
        'PluginSearchService: captcha required for ${error.pluginName}',
      );
      infoController.pluginSearchStatus[error.pluginName] =
          PluginSearchStatus.captcha;
      return;
    }
    if (error is NoResultException) {
      KazumiLogger().i(
        'PluginSearchService: no results for ${error.pluginName}',
      );
      infoController.pluginSearchStatus[error.pluginName] =
          PluginSearchStatus.noResult;
      return;
    }
    final name = error is SearchErrorException ? error.pluginName : plugin.name;
    KazumiLogger().w('PluginSearchService: search error for $name');
    infoController.pluginSearchStatus[name] = PluginSearchStatus.error;
  }

  void cancel() {
    _isCancelled = true;
    _cancelToken.cancel();
  }
}

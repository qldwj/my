import 'package:dio/dio.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:kazumi/services/plugin/plugin_credential_store.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/utils/async_session.dart';

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
        if (plugin.useLogin && !PluginCookieManager.instance.hasLoggedIn(plugin.name)) {
          // Cookie 未保存，尝试自动刷新：用保存的账号调用 auth/login
          final cred = PluginCredentialStore.instance.load(plugin.name);
          if (cred != null) {
            final refreshed = await _tryAutoRefresh(plugin, cred.$1, cred.$2);
            if (!refreshed) {
              infoController.pluginSearchStatus[pluginName] = PluginSearchStatus.login;
              return;
            }
            // 刷新成功，继续搜索
          } else {
            infoController.pluginSearchStatus[pluginName] = PluginSearchStatus.login;
            return;
          }
        }
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
            if (child.useLogin &&
                !PluginCookieManager.instance.hasLoggedIn(child.name)) {
              final cred = PluginCredentialStore.instance.load(child.name);
              if (cred != null) {
                final refreshed = await _tryAutoRefresh(child, cred.$1, cred.$2);
                if (!refreshed) {
                  infoController.pluginSearchStatus[pluginName] = PluginSearchStatus.login;
                  return;
                }
              } else {
                infoController.pluginSearchStatus[pluginName] = PluginSearchStatus.login;
                return;
              }
            }
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
    await Future.wait(
      plugins.map((plugin) => _queryPlugin(plugin, keyword)),
    );
  }

  Future<void> _queryPlugin(Plugin plugin, String keyword) async {
    if (_isCancelled) return;
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

  /// 使用保存的账号密码调用 auth/login 自动刷新 Cookie
  Future<bool> _tryAutoRefresh(Plugin plugin, String username, String password) async {
    try {
      final dio = Dio();
      final resp = await dio.post(
        '${plugin.baseUrl}api/auth/login',
        data: {'username': username, 'password': password},
        options: Options(headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-App-Name': 'cyc_web',
          'X-App-Version': 'cycweb',
          'Origin': plugin.baseUrl,
          'Referer': plugin.baseUrl,
        }, receiveTimeout: const Duration(seconds: 10)),
      );
      if (resp.statusCode == 200 && resp.data is Map && resp.data['code'] == 0) {
        final token = resp.data['data']?['access_token'] ?? resp.data['data']?['token'] ?? '';
        if (token.toString().isNotEmpty) {
          final cookieStr = 'access_token=$token';
          await PluginCookieManager.instance.saveFromWebView(plugin.name, plugin.baseUrl, cookieStr);
          KazumiLogger().i('[PluginSearch] 自动刷新 Token 成功: ${plugin.name}');
          return true;
        }
      }
      KazumiLogger().i('[PluginSearch] 自动刷新 Token 失败: ${resp.data}');
      return false;
    } catch (e) {
      KazumiLogger().i('[PluginSearch] 自动刷新异常: $e');
      return false;
    }
  }
}

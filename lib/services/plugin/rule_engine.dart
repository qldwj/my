import 'package:dio/dio.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/animeko_rule_config.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'package:kazumi/services/plugin/css_rule_strategy.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:kazumi/services/plugin/rss_rule_strategy.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/plugin/xpath_rule_strategy.dart';

abstract interface class RuleRequestExecutor {
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  });
}

class RuleEngine {
  RuleEngine({
    RuleRequestExecutor? requestExecutor,
    ApiRuleStrategy apiStrategy = const ApiRuleStrategy(),
    XPathRuleStrategy xpathStrategy = const XPathRuleStrategy(),
    CssRuleStrategy cssStrategy = const CssRuleStrategy(),
    RssRuleStrategy rssStrategy = const RssRuleStrategy(),
    bool logFailures = true,
  })  : _requestExecutor = requestExecutor ?? _DefaultRuleRequestExecutor(),
        _apiStrategy = apiStrategy,
        _xpathStrategy = xpathStrategy,
        _cssStrategy = cssStrategy,
        _rssStrategy = rssStrategy,
        _logFailures = logFailures;

  final RuleRequestExecutor _requestExecutor;
  final ApiRuleStrategy _apiStrategy;
  final XPathRuleStrategy _xpathStrategy;
  final CssRuleStrategy _cssStrategy;
  final RssRuleStrategy _rssStrategy;
  final bool _logFailures;

  Future<RuleSearchTrace> search(
    RuleExecutionConfig config,
    String keyword, {
    CancelToken? cancelToken,
  }) async {
    late final PreparedRuleRequest request;
    try {
      request = _prepareSearchRequest(config, keyword);
    } catch (error, stackTrace) {
      _logFailure(config, 'search request preparation', error, stackTrace);
      throw SearchErrorException(config.pluginName, cause: error);
    }

    final raw = await _executeRequest(
      request,
      config,
      phase: 'search request',
      wrapError: (error) =>
          SearchErrorException(config.pluginName, cause: error),
      cancelToken: cancelToken,
    );
    try {
      final parsed = _parseSearchResponse(raw, config);
      if (parsed.items.isEmpty) {
        throw NoResultException(config.pluginName);
      }
      _logDiagnostics(config, 'search', parsed.diagnostics);
      return RuleSearchTrace(
        rawResponse: raw,
        response: PluginSearchResponse(
          pluginName: config.pluginName,
          data: parsed.items,
        ),
        matchedFragments: parsed.matchedFragments,
        diagnostics: parsed.diagnostics,
      );
    } on CaptchaRequiredException {
      rethrow;
    } on NoResultException {
      rethrow;
    } catch (error, stackTrace) {
      if (_isCancellation(error)) rethrow;
      _logFailure(config, 'search response parsing', error, stackTrace);
      throw SearchErrorException(config.pluginName, cause: error);
    }
  }

  Future<RuleChapterTrace> queryChapters(
    RuleExecutionConfig config,
    String source, {
    CancelToken? cancelToken,
  }) async {
    late final PreparedRuleRequest request;
    try {
      request = _prepareChapterRequest(config, source);
    } catch (error, stackTrace) {
      _logFailure(config, 'chapter request preparation', error, stackTrace);
      throw ChapterErrorException(config.pluginName, cause: error);
    }

    final raw = await _executeRequest(
      request,
      config,
      phase: 'chapter request',
      wrapError: (error) =>
          ChapterErrorException(config.pluginName, cause: error),
      cancelToken: cancelToken,
    );
    try {
      final parsed = _parseChapterResponse(raw, config, source: source);
      if (parsed.roads.isEmpty) {
        throw ChapterErrorException(config.pluginName);
      }
      _logDiagnostics(config, 'chapter', parsed.diagnostics);
      return RuleChapterTrace(
        rawResponse: raw,
        roads: parsed.roads,
        diagnostics: parsed.diagnostics,
      );
    } on ChapterErrorException {
      rethrow;
    } catch (error, stackTrace) {
      if (_isCancellation(error)) rethrow;
      _logFailure(config, 'chapter response parsing', error, stackTrace);
      throw ChapterErrorException(config.pluginName, cause: error);
    }
  }

  // ------------------------------------------------------------------
  // CSS / XPath / API dispatch
  // ------------------------------------------------------------------

  PreparedRuleRequest _prepareSearchRequest(
    RuleExecutionConfig config,
    String keyword,
  ) {
    if (config.searchMode == RuleMode.rss) {
      return _rssStrategy.prepareSearchRequest(config.searchUrl, keyword);
    }
    if (config.searchMode == RuleMode.css) {
      final animeko = config.animekoConfig;
      if (animeko == null) {
        throw const CssRuleFormatException(
          'CSS 模式缺少 animekoConfig',
        );
      }
      return _cssStrategy.prepareSearchRequest(animeko, keyword);
    }
    if (config.searchMode == RuleMode.api) {
      return _apiStrategy.prepareRequest(
        config.searchApiConfig.request,
        <String, Object?>{'keyword': keyword},
      );
    }
    return _xpathStrategy.prepareSearchRequest(config, keyword);
  }

  RuleSearchParseResult _parseSearchResponse(
    String raw,
    RuleExecutionConfig config,
  ) {
    if (config.searchMode == RuleMode.rss) {
      return _rssStrategy.parseSearch(raw);
    }
    if (config.searchMode == RuleMode.css) {
      final animeko = config.animekoConfig;
      if (animeko == null) {
        throw const CssRuleFormatException(
          'CSS 模式缺少 animekoConfig',
        );
      }
      return _cssStrategy.parseSearch(raw, animeko);
    }
    if (config.searchMode == RuleMode.api) {
      return _apiStrategy.parseSearch(raw, config.searchApiConfig);
    }
    return _xpathStrategy.parseSearch(raw, config);
  }

  PreparedRuleRequest _prepareChapterRequest(
    RuleExecutionConfig config,
    String source,
  ) {
    // RSS: no chapters, just the magnet link itself as a single "episode"
    if (config.chapterMode == RuleMode.rss) {
      return PreparedRuleRequest(method: 'GET', url: source);
    }
    if (config.chapterMode == RuleMode.css) {
      final animeko = config.animekoConfig;
      if (animeko == null) {
        throw const CssRuleFormatException(
          'CSS 模式缺少 animekoConfig',
        );
      }
      return _cssStrategy.prepareChapterRequest(animeko, source);
    }
    if (config.chapterMode == RuleMode.api) {
      return _apiStrategy.prepareRequest(
        config.chapterApiConfig.request,
        <String, Object?>{'source': source},
      );
    }
    return _xpathStrategy.prepareChapterRequest(config, source);
  }

  RuleChapterParseResult _parseChapterResponse(
    String raw,
    RuleExecutionConfig config, {
    required String source,
  }) {
    // RSS: return the source (magnet link) as a single-episode road
    if (config.chapterMode == RuleMode.rss) {
      final roads = [
        Road(
          name: '下载',
          data: [source],
          identifier: ['资源'],
        ),
      ];
      return RuleChapterParseResult(roads: roads);
    }
    if (config.chapterMode == RuleMode.css) {
      final animeko = config.animekoConfig;
      if (animeko == null) {
        throw const CssRuleFormatException(
          'CSS 模式缺少 animekoConfig',
        );
      }
      return _cssStrategy.parseChapters(raw, animeko);
    }
    if (config.chapterMode == RuleMode.api) {
      return _apiStrategy.parseChapters(
        raw,
        config.chapterApiConfig,
        source: source,
        baseUrl: config.baseUrl,
      );
    }
    return _xpathStrategy.parseChapters(raw, config);
  }

  Future<String> _executeRequest(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    required String phase,
    required Object Function(Object error) wrapError,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _requestExecutor.execute(
        request,
        config,
        cancelToken: cancelToken,
      );
    } catch (error, stackTrace) {
      if (_isCancellation(error)) rethrow;
      _logFailure(config, phase, error, stackTrace);
      throw wrapError(error);
    }
  }

  bool _isCancellation(Object error) {
    return error is NetworkException &&
        error.type == NetworkExceptionType.cancel;
  }

  /// Surfaces partially-skipped nodes so incomplete results are traceable
  /// from logs even when the rule succeeds overall.
  void _logDiagnostics(
    RuleExecutionConfig config,
    String phase,
    List<String> diagnostics,
  ) {
    if (!_logFailures || diagnostics.isEmpty) return;
    final preview = diagnostics.take(3).join('; ');
    KazumiLogger().w(
      'Plugin: ${config.pluginName} $phase skipped ${diagnostics.length} '
      'node(s): $preview',
    );
  }

  void _logFailure(
    RuleExecutionConfig config,
    String phase,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!_logFailures) return;
    KazumiLogger().w(
      'Plugin: ${config.pluginName} $phase failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _DefaultRuleRequestExecutor implements RuleRequestExecutor {
  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    final cookieHeader = request.includeCookies
        ? await _cookieHeaderFor(config.pluginName, request.url)
        : '';
    final headers = <String, dynamic>{
      'referer': '${config.baseUrl}/',
      if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
      ...request.headers,
    };
    if (request.method == 'POST') {
      switch (request.bodyType) {
        case ApiBodyType.json:
          headers.putIfAbsent('Content-Type', () => 'application/json');
          break;
        case ApiBodyType.form:
          headers.putIfAbsent(
            'Content-Type',
            () => 'application/x-www-form-urlencoded',
          );
          break;
      }
    }
    return PluginSiteClient.instance.requestText(
      request.url,
      method: request.method,
      headers: headers,
      queryParameters: request.query,
      data: request.method == 'POST' ? request.body : null,
      cancelToken: cancelToken,
    );
  }

  Future<String> _cookieHeaderFor(String pluginName, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    try {
      final cookies =
          await PluginCookieManager.instance.loadForRequest(pluginName, uri);
      return cookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    } catch (_) {
      return '';
    }
  }
}

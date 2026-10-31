import 'package:yhdm/modules/roads/road_module.dart';
import 'package:yhdm/modules/search/plugin_search_module.dart';
import 'package:yhdm/plugins/anti_crawler_config.dart';
import 'package:yhdm/plugins/api_rule_config.dart';
import 'package:yhdm/plugins/animeko_rule_config.dart';
import 'package:yhdm/request/config/api_endpoints.dart';
import 'package:yhdm/services/plugin/api_rule_engine.dart';
import 'package:yhdm/services/plugin/css_rule_strategy.dart';
import 'package:yhdm/utils/episode_url.dart';
import 'package:yhdm/utils/http_headers.dart';

export 'package:yhdm/services/plugin/rule_engine_models.dart'
    show
        CaptchaRequiredException,
        NoResultException,
        SearchErrorException,
        ChapterErrorException;

class Plugin {
  static final RuleEngine _ruleEngine = RuleEngine();

  String api;
  String type;
  String name;
  String version;
  bool muliSources;

  /// Legacy schema field retained for rule import/export compatibility.
  bool useWebview;

  /// Legacy schema field retained for rule import/export compatibility.
  bool useNativePlayer;
  bool usePost;
  bool useLegacyParser;
  bool adBlocker;
  String userAgent;
  String baseUrl;
  String searchURL;
  String searchList;
  String searchName;
  String searchResult;
  String chapterRoads;
  String chapterResult;
  String referer;

  /// 🆕 此规则需要登录验证时的登录页地址（[needLogin] 为 true 时用内置 WebView 打开它）。
  /// 规则 JSON 键为 `loginURL` 或 `loginUrl`。
  String loginUrl;

  /// 🆕 此规则的动漫图标 URL（规则 JSON 键为 `icon`）。为空或加载失败时显示默认图标。
  String icon;
  String searchMode;
  String chapterMode;
  ApiSearchConfig searchApiConfig;
  ApiChapterConfig chapterApiConfig;
  AntiCrawlerConfig antiCrawlerConfig;

  /// 🆕 登录检测配置（token 认证站点用）。非空时 App 通过此接口
  /// 主动校验登录态，而不是依赖 Cookie 的 expires 判断过期。
  PluginCheckConfig? checkConfig;

  /// 🆕 登录方式配置（规则键 `login`）。非空时决定登录模式
  /// （webview/xpath/api）；空则回退为仅用 [loginUrl] 的 webview 登录。
  PluginLoginConfig? loginConfig;

  /// Optional animeko web-selector rule config. When non-null and
  /// [searchMode]/[chapterMode] is `RuleMode.css`, the rule engine uses
  /// [CssRuleStrategy] with this config instead of XPath/API strategies.
  AnimekoWebSelectorRule? animekoConfig;

  /// Whether this rule is enabled for search. Disabled rules are skipped
  /// during queryAllSource and don't appear in source selection tabs.
  bool enabled;

  /// 🆕 此规则是否需要登录验证后才能观看（登录后通过内置 WebView 保存 Cookie，
  /// 后续观看自动携带）。规则 JSON 可通过 `needLogin: true` 标记。
  bool needLogin;

  Plugin({
    required this.api,
    required this.type,
    required this.name,
    required this.version,
    required this.muliSources,
    required this.useWebview,
    required this.useNativePlayer,
    required this.usePost,
    required this.useLegacyParser,
    required this.adBlocker,
    required this.userAgent,
    required this.baseUrl,
    required this.searchURL,
    required this.searchList,
    required this.searchName,
    required this.searchResult,
    required this.chapterRoads,
    required this.chapterResult,
    required this.referer,
    this.loginUrl = '',
    this.icon = '',
    this.searchMode = RuleMode.xpath,
    this.chapterMode = RuleMode.xpath,
    ApiSearchConfig? searchApiConfig,
    ApiChapterConfig? chapterApiConfig,
    AntiCrawlerConfig? antiCrawlerConfig,
    this.animekoConfig,
    this.checkConfig,
    this.loginConfig,
    this.enabled = true,
    this.needLogin = false,
  })  : searchApiConfig = searchApiConfig ?? ApiSearchConfig(),
        chapterApiConfig = chapterApiConfig ?? ApiChapterConfig(),
        antiCrawlerConfig = antiCrawlerConfig ?? AntiCrawlerConfig.empty();

  factory Plugin.fromJson(Map<String, dynamic> json) {
    return Plugin(
      api: json['api']?.toString() ?? '1',
      type: json['type'] as String? ?? 'anime',
      name: json['name'] as String? ?? '',
      version: json['version']?.toString() ?? '',
      muliSources: json['muliSources'] as bool? ?? true,
      useWebview: json['useWebview'] as bool? ?? true,
      useNativePlayer: json['useNativePlayer'] as bool? ?? true,
      usePost: json['usePost'] ?? false,
      useLegacyParser: json['useLegacyParser'] ?? false,
      adBlocker: json['adBlocker'] ?? false,
      userAgent: json['userAgent'] as String? ?? '',
      baseUrl: json['baseURL'] as String? ?? '',
      searchURL: json['searchURL'] as String? ?? '',
      searchList: json['searchList'] as String? ?? '',
      searchName: json['searchName'] as String? ?? '',
      searchResult: json['searchResult'] as String? ?? '',
      chapterRoads: json['chapterRoads'] as String? ?? '',
      chapterResult: json['chapterResult'] as String? ?? '',
      referer: json['referer'] ?? '',
      loginUrl: json['loginURL'] as String? ?? json['loginUrl'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      searchMode: RuleMode.normalize(json['searchMode']),
      chapterMode: RuleMode.normalize(json['chapterMode']),
      searchApiConfig: json['searchApiConfig'] is Map
          ? ApiSearchConfig.fromJson(
              Map<String, dynamic>.from(json['searchApiConfig']),
            )
          : ApiSearchConfig(),
      chapterApiConfig: json['chapterApiConfig'] is Map
          ? ApiChapterConfig.fromJson(
              Map<String, dynamic>.from(json['chapterApiConfig']),
            )
          : ApiChapterConfig(),
      checkConfig: json['check'] is Map
          ? PluginCheckConfig.fromJson(
              Map<String, dynamic>.from(json['check']),
            )
          : null,
      loginConfig: json['login'] is Map
          ? PluginLoginConfig.fromJson(
              Map<String, dynamic>.from(json['login']),
            )
          : null,
      antiCrawlerConfig: json['antiCrawlerConfig'] != null
          ? AntiCrawlerConfig.fromJson(
              Map<String, dynamic>.from(json['antiCrawlerConfig']),
            )
          : AntiCrawlerConfig.empty(),
      animekoConfig: json[animekoConfigKey] is Map
          ? AnimekoWebSelectorRule.fromJson(
              Map<String, dynamic>.from(json[animekoConfigKey]),
            )
          : null,
      enabled: json['enabled'] as bool? ?? true,
      needLogin: json['needLogin'] as bool? ?? false,
    );
  }

  factory Plugin.fromTemplate() {
    return Plugin(
      api: ApiEndpoints.apiLevel.toString(),
      type: 'anime',
      name: '',
      version: '',
      muliSources: true,
      useWebview: true,
      useNativePlayer: true,
      usePost: false,
      useLegacyParser: false,
      adBlocker: false,
      userAgent: '',
      baseUrl: '',
      searchURL: '',
      searchList: '',
      searchName: '',
      searchResult: '',
      chapterRoads: '',
      chapterResult: '',
      referer: '',
      loginUrl: '',
      icon: '',
      searchMode: RuleMode.xpath,
      chapterMode: RuleMode.xpath,
      searchApiConfig: ApiSearchConfig(),
      chapterApiConfig: ApiChapterConfig(),
      antiCrawlerConfig: AntiCrawlerConfig.empty(),
      animekoConfig: null,
      enabled: true,
      needLogin: false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'api': api,
      'type': type,
      'name': name,
      'version': version,
      'muliSources': muliSources,
      'useWebview': useWebview,
      'useNativePlayer': useNativePlayer,
      'usePost': usePost,
      'useLegacyParser': useLegacyParser,
      'adBlocker': adBlocker,
      'userAgent': userAgent,
      'baseURL': baseUrl,
      'searchURL': searchURL,
      'searchList': searchList,
      'searchName': searchName,
      'searchResult': searchResult,
      'chapterRoads': chapterRoads,
      'chapterResult': chapterResult,
      'referer': referer,
      'loginURL': loginUrl,
      'icon': icon,
      'searchMode': searchMode,
      'chapterMode': chapterMode,
      // Persisting re-serializes the whole plugin list, so a configured API
      // rule must survive even while the mode points at XPath.
      if (searchMode == RuleMode.api || searchApiConfig.request.url.isNotEmpty)
        'searchApiConfig': searchApiConfig.toJson(),
      if (chapterMode == RuleMode.api ||
          chapterApiConfig.request.url.isNotEmpty)
        'chapterApiConfig': chapterApiConfig.toJson(),
      if (checkConfig != null) 'check': checkConfig!.toJson(),
      if (loginConfig != null) 'login': loginConfig!.toJson(),
      'antiCrawlerConfig': antiCrawlerConfig.toJson(),
      if (animekoConfig != null)
        animekoConfigKey: animekoConfig!.toJson(),
      'enabled': enabled,
      'needLogin': needLogin,
    };
  }

  bool get usesApiSearch => searchMode == RuleMode.api;

  /// 🆕 是否配置了基于 API 的登录检测（token 认证站点）。
  bool get usesApiCheck => checkConfig != null && checkConfig!.request.url.isNotEmpty;

  bool get usesCssSearch => searchMode == RuleMode.css;

  bool get usesRssSearch => searchMode == RuleMode.rss;

  bool get requiresNewerClient => int.parse(api) > ApiEndpoints.apiLevel;

  RuleExecutionConfig get _executionConfig => RuleExecutionConfig(
        pluginName: name,
        baseUrl: baseUrl,
        usePost: usePost,
        searchMode: searchMode,
        chapterMode: chapterMode,
        searchUrl: searchURL,
        searchList: searchList,
        searchName: searchName,
        searchResult: searchResult,
        chapterRoads: chapterRoads,
        chapterResult: chapterResult,
        searchApiConfig: searchApiConfig,
        chapterApiConfig: chapterApiConfig,
        antiCrawlerConfig: antiCrawlerConfig,
        animekoConfig: animekoConfig,
      );

  Future<RuleSearchTrace> traceSearch(
    String keyword, {
    RuleCancelToken? cancelToken,
  }) {
    return _ruleEngine.search(
      _executionConfig,
      keyword,
      cancelToken: cancelToken,
    );
  }

  /// 尝试直接解析验证后收割的页面 HTML 为搜索结果（用于验证码通过后）。
  /// 无法解析时返回 null，由调用方回落到重新检索。
  PluginSearchResponse? parseHarvestedSearch(String html) {
    return _ruleEngine.tryParseHarvestedSearch(_executionConfig, html);
  }

  Future<RuleChapterTrace> traceChapters(
    String source, {
    RuleCancelToken? cancelToken,
  }) {
    return _ruleEngine.queryChapters(
      _executionConfig,
      source,
      cancelToken: cancelToken,
    );
  }

  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    try {
      return (await traceSearch(keyword, cancelToken: cancelToken)).response;
    } on CaptchaRequiredException {
      rethrow;
    } on NoResultException {
      rethrow;
    } on SearchErrorException {
      if (shouldRethrow) rethrow;
      return PluginSearchResponse(pluginName: name, data: <SearchItem>[]);
    }
  }

  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) async {
    return (await traceChapters(source, cancelToken: cancelToken)).roads;
  }

  String buildFullUrl(String urlItem) {
    return normalizeEpisodeUrl(baseUrl, urlItem);
  }

  /// Headers used when resolving or downloading the final media resource.
  /// When in CSS/animeko mode, uses the animeko matchVideo headers.
  /// RSS sources need no special headers.
  Map<String, String> buildHttpHeaders() {
    if (usesRssSearch) {
      return {};
    }
    if (usesCssSearch && animekoConfig != null) {
      return const CssRuleStrategy().buildVideoHeaders(animekoConfig!);
    }
    return {
      'user-agent': userAgent.isEmpty ? getRandomUA() : userAgent,
      if (referer.isNotEmpty) 'referer': referer,
    };
  }

  /// Whether the video source for this plugin is the final media URL directly
  /// (e.g. RSS magnet links), skipping WebView resolution.
  bool get hasDirectMediaUrl => usesRssSearch;

  /// Extracts the video URL from a playback page HTML using the Animeko
  /// matchVideo regex rules. Only applicable in CSS mode.
  /// Returns an empty string if no match or not in CSS mode.
  String extractVideoUrlFromPage(String pageHtml) {
    if (usesCssSearch && animekoConfig != null) {
      return const CssRuleStrategy().extractVideoUrl(pageHtml, animekoConfig!);
    }
    return '';
  }

  /// 🆕 递归解析视频直链（支持 Animeko 多级嵌套 URL）。
  /// [fetcher] 用于抓取嵌套页（应携带 matchVideo.cookies / referer）。
  Future<String> resolveVideoUrlFromPage(
    String pageHtml, {
    Future<String> Function(String url)? fetcher,
  }) async {
    if (usesCssSearch && animekoConfig != null) {
      return const CssRuleStrategy()
          .resolveVideoUrl(pageHtml, animekoConfig!, fetcher: fetcher);
    }
    return '';
  }
}

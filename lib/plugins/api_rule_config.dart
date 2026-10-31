class RuleMode {
  static const String xpath = 'xpath';
  static const String api = 'api';
  static const String css = 'css';
  static const String rss = 'rss';

  static String normalize(Object? value) {
    if (value == api) return api;
    if (value == css) return css;
    if (value == rss) return rss;
    return xpath;
  }
}

class ApiBodyType {
  static const String none = 'none';
  static const String json = 'json';
  static const String form = 'form';

  static String normalize(Object? value) {
    return switch (value) {
      json => json,
      form => form,
      _ => none,
    };
  }
}

class ApiChapterFormat {
  static const String nested = 'nested';
  static const String delimited = 'delimited';

  static String normalize(Object? value) {
    return value == delimited ? delimited : nested;
  }
}

class ApiRequestConfig {
  String method;
  String url;
  Map<String, dynamic> headers;
  Map<String, dynamic> query;
  String bodyType;
  dynamic body;

  ApiRequestConfig({
    this.method = 'GET',
    this.url = '',
    Map<String, dynamic>? headers,
    Map<String, dynamic>? query,
    this.bodyType = ApiBodyType.none,
    this.body,
  })  : headers = headers ?? <String, dynamic>{},
        query = query ?? <String, dynamic>{};

  factory ApiRequestConfig.fromJson(Map<String, dynamic> json) {
    return ApiRequestConfig(
      method: (json['method'] as String? ?? 'GET').toUpperCase(),
      url: json['url'] as String? ?? '',
      headers: _asStringMap(json['headers']),
      query: _asStringMap(json['query']),
      bodyType: ApiBodyType.normalize(json['bodyType']),
      body: json['body'],
    );
  }

  Map<String, dynamic> toJson() => {
        'method': method.toUpperCase(),
        'url': url,
        if (headers.isNotEmpty) 'headers': headers,
        if (query.isNotEmpty) 'query': query,
        if (bodyType != ApiBodyType.none) 'bodyType': bodyType,
        if (bodyType != ApiBodyType.none && body != null) 'body': body,
      };
}

class ApiSearchConfig {
  ApiRequestConfig request;
  String listPath;
  String namePath;
  String sourcePath;

  /// Detail page URL built by replacing `@source`; empty keeps the raw value.
  final String sourceTemplate;

  ApiSearchConfig({
    ApiRequestConfig? request,
    this.listPath = r'$.data[*]',
    this.namePath = r'$.name',
    this.sourcePath = r'$.url',
    String sourceTemplate = '',
  })  : request = request ?? ApiRequestConfig(),
        sourceTemplate = sourceTemplate.trim();

  factory ApiSearchConfig.fromJson(Map<String, dynamic> json) {
    return ApiSearchConfig(
      request: ApiRequestConfig.fromJson(_asStringMap(json['request'])),
      listPath: json['listPath'] as String? ?? r'$.data[*]',
      namePath: json['namePath'] as String? ?? r'$.name',
      sourcePath: json['sourcePath'] as String? ?? r'$.url',
      sourceTemplate: json['sourceTemplate'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'request': request.toJson(),
        'listPath': listPath,
        'namePath': namePath,
        'sourcePath': sourcePath,
        if (sourceTemplate.isNotEmpty) 'sourceTemplate': sourceTemplate,
      };
}

class ApiEpisodePageConfig {
  /// Template for the final playback page URL.
  String url;

  /// Query parameters rendered with response and episode index variables.
  Map<String, dynamic> query;

  ApiEpisodePageConfig({
    this.url = '',
    Map<String, dynamic>? query,
  }) : query = query ?? <String, dynamic>{};

  factory ApiEpisodePageConfig.fromJson(Map<String, dynamic> json) {
    return ApiEpisodePageConfig(
      url: json['url'] as String? ?? '',
      query: _asStringMap(json['query']),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'query': query,
      };
}

class ApiChapterConfig {
  ApiRequestConfig request;
  String format;

  // Nested JSON response mapping.
  String roadsPath;
  String roadNamePath;
  String episodesPath;
  String episodeNamePath;

  /// JSONPath for a playback entry URL (page URL or direct media URL).
  /// May be empty when [episodePage] constructs the final playback page URL.
  String episodeUrlPath;

  // Delimited string response mapping.
  String roadNamesPath;
  String roadEpisodesPath;
  String roadSeparator;
  String episodeSeparator;
  String fieldSeparator;

  /// Named JSONPath captures over the chapter response, exposed as template
  /// variables to [episodePage].
  Map<String, String> variables;

  /// Optional final playback page template used instead of a response URL.
  ApiEpisodePageConfig? episodePage;

  ApiChapterConfig({
    ApiRequestConfig? request,
    this.format = ApiChapterFormat.nested,
    this.roadsPath = r'$.data.roads[*]',
    this.roadNamePath = r'$.name',
    this.episodesPath = r'$.episodes[*]',
    this.episodeNamePath = r'$.name',
    this.episodeUrlPath = r'$.url',
    this.roadNamesPath = '',
    this.roadEpisodesPath = '',
    this.roadSeparator = r'$$$',
    this.episodeSeparator = '#',
    this.fieldSeparator = r'$',
    Map<String, String>? variables,
    this.episodePage,
  })  : request = request ?? ApiRequestConfig(),
        variables = variables ?? <String, String>{};

  factory ApiChapterConfig.fromJson(Map<String, dynamic> json) {
    final rawVariables = _asStringMap(json['variables']);
    return ApiChapterConfig(
      request: ApiRequestConfig.fromJson(_asStringMap(json['request'])),
      format: ApiChapterFormat.normalize(json['format']),
      roadsPath: json['roadsPath'] as String? ?? r'$.data.roads[*]',
      roadNamePath: json['roadNamePath'] as String? ?? r'$.name',
      episodesPath: json['episodesPath'] as String? ?? r'$.episodes[*]',
      episodeNamePath: json['episodeNamePath'] as String? ?? r'$.name',
      episodeUrlPath: json['episodeUrlPath'] as String? ?? r'$.url',
      roadNamesPath: json['roadNamesPath'] as String? ?? '',
      roadEpisodesPath: json['roadEpisodesPath'] as String? ?? '',
      roadSeparator: json['roadSeparator'] as String? ?? r'$$$',
      episodeSeparator: json['episodeSeparator'] as String? ?? '#',
      fieldSeparator: json['fieldSeparator'] as String? ?? r'$',
      variables: rawVariables.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      episodePage: json['episodePage'] is Map
          ? ApiEpisodePageConfig.fromJson(_asStringMap(json['episodePage']))
          : null,
    );
  }

  /// Whether any nested-format field deviates from its default. Persisting
  /// re-serializes every plugin, so a customized inactive side must survive
  /// even while [format] points at the other one.
  bool get _hasNestedConfig =>
      roadsPath != r'$.data.roads[*]' ||
      roadNamePath != r'$.name' ||
      episodesPath != r'$.episodes[*]' ||
      episodeNamePath != r'$.name' ||
      episodeUrlPath != r'$.url';

  bool get _hasDelimitedConfig =>
      roadNamesPath.isNotEmpty || roadEpisodesPath.isNotEmpty;

  /// Serializes the active [format]'s fields, plus the inactive format's
  /// fields when they carry non-default configuration.
  Map<String, dynamic> toJson() => {
        'request': request.toJson(),
        'format': format,
        if (format == ApiChapterFormat.nested || _hasNestedConfig) ...{
          'roadsPath': roadsPath,
          'roadNamePath': roadNamePath,
          'episodesPath': episodesPath,
          'episodeNamePath': episodeNamePath,
          'episodeUrlPath': episodeUrlPath,
        },
        if (format == ApiChapterFormat.delimited || _hasDelimitedConfig) ...{
          'roadNamesPath': roadNamesPath,
          'roadEpisodesPath': roadEpisodesPath,
          'roadSeparator': roadSeparator,
          'episodeSeparator': episodeSeparator,
          'fieldSeparator': fieldSeparator,
        },
        if (variables.isNotEmpty) 'variables': variables,
        if (episodePage != null) 'episodePage': episodePage!.toJson(),
      };
}

/// 登录检测（check）配置
///
/// 当规则使用 token 认证（而非 Cookie）时，App 无法从 Cookie 的 expires
/// 判断登录是否过期。此配置让 App 主动调用一个校验接口，携带保存的 token
/// （`@token` 占位符会被替换），根据响应判定登录态是否有效。
class PluginCheckConfig {
  ApiRequestConfig request;

  /// 预期 HTTP 状态码（默认 200，视为有效）。
  int successStatus;

  /// 预期响应体 `code` 字段值（默认 0，视为有效）。
  /// 为 null 时忽略响应体，仅看 HTTP 状态码。
  int? successCode;

  /// 业务码所在 JSONPath，缺省 `$.code`。用于从响应体提取 `code` 字段。
  String successCodePath;

  /// token 占位符，会在请求 URL/Header/Body 中被替换为已保存的 token。
  String tokenPlaceholder;

  /// 检测模式：'api' 调接口（默认）；'local' 用本地 expiresAt 计算过期，不调接口；
  /// 'xpath' 打开 [Plugin.loginUrl] 检查页面是否出现 [xpath] 特征节点（已登录特征）。
  String mode;

  /// mode == 'xpath' 时的已登录特征 XPath：页面上出现该节点即判定已登录。
  String xpath;

  /// 是否为本地计算模式（不调接口，直接用保存的 expiresAt 判断过期）。
  bool get isLocal => mode == 'local';

  /// 是否为 XPath 特征检测模式。
  bool get isXpath => mode == 'xpath';

  PluginCheckConfig({
    ApiRequestConfig? request,
    this.successStatus = 200,
    this.successCode = 0,
    this.successCodePath = r'$.code',
    this.tokenPlaceholder = '@token',
    this.mode = 'api',
    this.xpath = '',
  }) : request = request ?? ApiRequestConfig();

  factory PluginCheckConfig.fromJson(Map<String, dynamic> json) {
    final rawRequest = json['request'];
    return PluginCheckConfig(
      request: rawRequest is Map
          ? ApiRequestConfig.fromJson(
              Map<String, dynamic>.from(rawRequest),
            )
          : ApiRequestConfig(),
      successStatus: (json['successStatus'] as int?) ?? 200,
      successCode: json['successCode'] is int
          ? (json['successCode'] as int)
          : null,
      successCodePath: (json['successCodePath'] as String?) ?? r'$.code',
      tokenPlaceholder: (json['tokenPlaceholder'] as String?) ?? '@token',
      mode: (json['mode'] as String?) ?? 'api',
      xpath: (json['xpath'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'request': request.toJson(),
        'successStatus': successStatus,
        if (successCode != null) 'successCode': successCode,
        if (successCodePath != r'$.code') 'successCodePath': successCodePath,
        if (tokenPlaceholder != '@token') 'tokenPlaceholder': tokenPlaceholder,
        if (mode != 'api') 'mode': mode,
        if (xpath.isNotEmpty) 'xpath': xpath,
      };
}

/// API 登录配置（`login.mode == 'api'`）
///
/// App 直接请求登录接口，从响应提取 token/cookie 保存。
class ApiLoginConfig {
  ApiRequestConfig request;

  /// body/query 中账号字段名（值占位 `@account` 会被替换为输入的账号）。
  String accountField;

  /// body/query 中密码字段名（值占位 `@password` 会被替换为输入的密码）。
  String passwordField;

  /// 从响应提取 token 的 JSONPath（如 `$.data.token`）。
  String tokenPath;

  /// 从响应提取 cookie 的 JSONPath（cookie 认证站用，可空）。
  String cookiePath;

  /// 预期 HTTP 状态码（默认 200，视为成功）。
  int successStatus;

  /// 预期业务码（可选；与响应 `successCodePath` 处值匹配即成功）。
  int? successCode;

  /// 业务码所在 JSONPath，缺省 `$.code`。
  String successCodePath;

  ApiLoginConfig({
    ApiRequestConfig? request,
    this.accountField = '',
    this.passwordField = '',
    this.tokenPath = '',
    this.cookiePath = '',
    this.successStatus = 200,
    this.successCode,
    this.successCodePath = r'$.code',
  }) : request = request ?? ApiRequestConfig();

  factory ApiLoginConfig.fromJson(Map<String, dynamic> json) {
    final rawRequest = json['request'];
    return ApiLoginConfig(
      request: rawRequest is Map
          ? ApiRequestConfig.fromJson(
              Map<String, dynamic>.from(rawRequest),
            )
          : ApiRequestConfig(),
      accountField: (json['accountField'] as String?) ?? '',
      passwordField: (json['passwordField'] as String?) ?? '',
      tokenPath: (json['tokenPath'] as String?) ?? '',
      cookiePath: (json['cookiePath'] as String?) ?? '',
      successStatus: (json['successStatus'] as int?) ?? 200,
      successCode: json['successCode'] is int
          ? (json['successCode'] as int)
          : null,
      successCodePath: (json['successCodePath'] as String?) ?? r'$.code',
    );
  }

  Map<String, dynamic> toJson() => {
        'request': request.toJson(),
        if (accountField.isNotEmpty) 'accountField': accountField,
        if (passwordField.isNotEmpty) 'passwordField': passwordField,
        if (tokenPath.isNotEmpty) 'tokenPath': tokenPath,
        if (cookiePath.isNotEmpty) 'cookiePath': cookiePath,
        'successStatus': successStatus,
        if (successCode != null) 'successCode': successCode,
        if (successCodePath != r'$.code') 'successCodePath': successCodePath,
      };
}

/// 登录配置（规则键 `login`）
///
/// 决定登录方式：`webview`（内置浏览器登录页）/ `xpath`（登录弹窗表单自动填入）/ `api`（API 登录）。
class PluginLoginConfig {
  /// 'webview' | 'xpath' | 'api'。缺省 'webview'（仅用 [Plugin.loginUrl]）。
  String mode;

  /// mode == 'xpath' 时的登录弹窗字段。
  String accountXpath;
  String passwordXpath;
  String submitXpath;
  String successXpath;

  /// mode == 'api' 时的 API 登录配置。
  ApiLoginConfig? api;

  bool get isWebview => mode == 'webview';
  bool get isXpath => mode == 'xpath';
  bool get isApi => mode == 'api';

  PluginLoginConfig({
    this.mode = 'webview',
    this.accountXpath = '',
    this.passwordXpath = '',
    this.submitXpath = '',
    this.successXpath = '',
    this.api,
  });

  factory PluginLoginConfig.fromJson(Map<String, dynamic> json) {
    final rawApi = json['api'];
    return PluginLoginConfig(
      mode: (json['mode'] as String?) ?? 'webview',
      accountXpath: (json['xpath'] is Map)
          ? (json['xpath']['account'] as String? ?? '')
          : '',
      passwordXpath: (json['xpath'] is Map)
          ? (json['xpath']['password'] as String? ?? '')
          : '',
      submitXpath: (json['xpath'] is Map)
          ? (json['xpath']['submit'] as String? ?? '')
          : '',
      successXpath: (json['xpath'] is Map)
          ? (json['xpath']['success'] as String? ?? '')
          : '',
      api: rawApi is Map
          ? ApiLoginConfig.fromJson(Map<String, dynamic>.from(rawApi))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final xpath = <String, dynamic>{
      if (accountXpath.isNotEmpty) 'account': accountXpath,
      if (passwordXpath.isNotEmpty) 'password': passwordXpath,
      if (submitXpath.isNotEmpty) 'submit': submitXpath,
      if (successXpath.isNotEmpty) 'success': successXpath,
    };
    return {
      'mode': mode,
      if (xpath.isNotEmpty) 'xpath': xpath,
      if (api != null) 'api': api!.toJson(),
    };
  }
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

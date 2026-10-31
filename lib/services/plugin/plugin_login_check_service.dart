import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:yhdm/plugins/plugins.dart';
import 'package:yhdm/request/core/dio_factory.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/plugin/plugin_cookie_manager.dart';

/// 登录检测结果
class LoginCheckResult {
  /// 登录态是否有效。
  final bool valid;

  /// 是否保存过 token（token 认证站点）。
  final bool hasToken;

  /// HTTP 状态码（请求成功时）。
  final int? statusCode;

  /// 描述信息（调试用）。
  final String? message;

  const LoginCheckResult({
    required this.valid,
    required this.hasToken,
    this.statusCode,
    this.message,
  });
}

/// 基于规则 `check` 配置的登录态检测服务。
///
/// token 认证站点（如次元城）无法从 Cookie 的 expires 判断登录是否过期，
/// 此服务主动调用规则配置的校验接口（携带保存的 token），
/// 根据响应判定登录态是否有效。
///
/// - 无 `check` 配置：回退到 Cookie 有效期判断（[PluginCookieManager.hasSaved]）。
/// - 有 `check` 且 mode=api（默认）：读取 token，替换 `@token` 占位符，发起请求；
///   HTTP 状态码与响应体 `code` 均符合预期视为有效。
///   - HTTP 401/403 → 明确过期。
///   - 网络异常 → 保守视为有效（避免误判清除登录态）。
/// - 有 `check` 且 mode=local：不调接口，直接用保存的 expiresAt 本地判断过期。
class PluginLoginCheckService {
  PluginLoginCheckService._();
  static final PluginLoginCheckService instance = PluginLoginCheckService._();

  /// 检查插件登录态。
  Future<LoginCheckResult> check(Plugin plugin) async {
    // 本地计算模式：不调接口，直接用保存的 expiresAt 判断是否过期。
    if (plugin.checkConfig?.isLocal == true) {
      final localToken = PluginCookieManager.instance.tokenFor(plugin.name);
      if (localToken == null || localToken.isEmpty) {
        return const LoginCheckResult(
          valid: false,
          hasToken: false,
          message: '未保存 token',
        );
      }
      final expiresAt =
          PluginCookieManager.instance.tokenExpiresAt(plugin.name);
      // 无 expiresAt（会话级）保守视为有效；有则按本地时间判断。
      final valid = expiresAt == null || DateTime.now().isBefore(expiresAt);
      return LoginCheckResult(
        valid: valid,
        hasToken: true,
        message: valid ? '本地有效' : '本地已过期',
      );
    }

    // XPath 特征模式：Dio 抓取检测页面（携带保存的 cookie），用未登录/已登录
    // 特征 XPath 判定登录态（登录后昵称等动态特征无法固定时，可用未登录特征反向判定）。
    if (plugin.checkConfig?.isXpath == true) {
      return _checkXpath(plugin);
    }

    if (!plugin.usesApiCheck) {
      final valid = PluginCookieManager.instance.hasSaved(plugin.name);
      return LoginCheckResult(valid: valid, hasToken: valid);
    }

    final token = PluginCookieManager.instance.tokenFor(plugin.name);
    if (token == null || token.isEmpty) {
      return const LoginCheckResult(
        valid: false,
        hasToken: false,
        message: '未保存 token',
      );
    }

    final cfg = plugin.checkConfig!;
    final req = cfg.request;
    final ph = cfg.tokenPlaceholder;
    final url = _renderTemplate(req.url, token, ph);
    final headers = _renderMap(req.headers, token, ph);
    final query = _renderMap(req.query, token, ph);

    try {
      final response = await DioFactory.pluginDio.request<String>(
        url,
        queryParameters: query.isEmpty ? null : query,
        options: Options(
          method: req.method.toUpperCase(),
          responseType: ResponseType.plain,
          headers: headers,
        ),
      );
      final statusOk = response.statusCode == cfg.successStatus;
      final codeOk = _checkCode(response.data, cfg.successCode, cfg.successCodePath);
      final valid = statusOk && codeOk;
      return LoginCheckResult(
        valid: valid,
        hasToken: true,
        statusCode: response.statusCode,
        message: valid ? '有效' : 'token 失效（HTTP ${response.statusCode}）',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return LoginCheckResult(
          valid: false,
          hasToken: true,
          statusCode: status,
          message: 'token 失效（HTTP $status）',
        );
      }
      // 网络异常：保守视为有效，避免误判导致清除登录态
      KazumiLogger().w(
        '[LoginCheckService] ${plugin.name} check 网络异常，保留登录态: ${e.message}',
      );
      return LoginCheckResult(
        valid: true,
        hasToken: true,
        statusCode: status,
        message: '网络异常，保留登录态',
      );
    } catch (e) {
      KazumiLogger().w('[LoginCheckService] ${plugin.name} check 异常: $e');
      return LoginCheckResult(
        valid: true,
        hasToken: true,
        message: '检测异常，保留登录态',
      );
    }
  }

  /// 用【指定 token】（而非已保存的）校验登录态。
  ///
  /// 供登录页在保存 token 前调用：检测到 localStorage 中出现 token 时，
  /// 先调用规则 `check` 接口验证它是否为有效登录 token。
  /// 站点预置的干扰 token（如游客态、设备 token）会被此校验拦截，
  /// 避免「未登录就保存无效 token」导致的误判与登录死循环。
  Future<LoginCheckResult> checkToken(Plugin plugin, String token) async {
    // 统一剥离 `Bearer ` 前缀（部分站点 token 自带前缀，如次元城），
    // 保证规则 `Bearer @token` 拼接正确。
    token = _stripBearerPrefix(token);
    if (!plugin.usesApiCheck) {
      return LoginCheckResult(valid: token.isNotEmpty, hasToken: token.isNotEmpty);
    }
    if (token.isEmpty) {
      return const LoginCheckResult(valid: false, hasToken: false, message: 'token 为空');
    }
    final cfg = plugin.checkConfig!;
    final req = cfg.request;
    final ph = cfg.tokenPlaceholder;
    final url = _renderTemplate(req.url, token, ph);
    final headers = _renderMap(req.headers, token, ph);
    final query = _renderMap(req.query, token, ph);
    try {
      final response = await DioFactory.pluginDio.request<String>(
        url,
        queryParameters: query.isEmpty ? null : query,
        options: Options(
          method: req.method.toUpperCase(),
          responseType: ResponseType.plain,
          headers: headers,
        ),
      );
      final valid = response.statusCode == cfg.successStatus &&
          _checkCode(response.data, cfg.successCode, cfg.successCodePath);
      return LoginCheckResult(
        valid: valid,
        hasToken: true,
        statusCode: response.statusCode,
        message: valid ? '有效' : 'token 校验未通过（HTTP ${response.statusCode}）',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return LoginCheckResult(
          valid: false,
          hasToken: true,
          statusCode: status,
          message: 'token 失效（HTTP $status）',
        );
      }
      // 网络异常：保守视为有效，避免误判导致清除登录态
      KazumiLogger().w(
        '[LoginCheckService] ${plugin.name} checkToken 网络异常，保留登录态: ${e.message}',
      );
      return LoginCheckResult(
        valid: true,
        hasToken: true,
        statusCode: status,
        message: '网络异常，保留登录态',
      );
    } catch (e) {
      KazumiLogger().w('[LoginCheckService] ${plugin.name} checkToken 异常: $e');
      return LoginCheckResult(
        valid: true,
        hasToken: true,
        message: '检测异常，保留登录态',
      );
    }
  }

  /// XPath 特征检测：Dio 抓取 [PluginCheckConfig.url]（回退 [Plugin.loginUrl]）
  /// 页面（携带保存的 cookie），解析后按特征判定登录态。
  ///
  /// - 未登录特征 [xpathUnlogin] 非空且页面出现该节点 → 无效；
  /// - 已登录特征 [xpath] 非空且页面出现该节点 → 有效；
  /// - 仅配 [xpathUnlogin]（未登录特征）且其**不出现** → 有效。
  Future<LoginCheckResult> _checkXpath(Plugin plugin) async {
    final cfg = plugin.checkConfig!;
    if (!cfg.hasXpathFeature) {
      final valid = PluginCookieManager.instance.hasSaved(plugin.name);
      return LoginCheckResult(
        valid: valid,
        hasToken: valid,
        message: valid ? '已保存登录态' : '未保存登录态',
      );
    }
    final url = cfg.url.isNotEmpty ? cfg.url : plugin.loginUrl;
    if (url.isEmpty) {
      final valid = PluginCookieManager.instance.hasSaved(plugin.name);
      return LoginCheckResult(
        valid: valid,
        hasToken: valid,
        message: valid ? '已保存登录态' : '未保存登录态',
      );
    }
    final cookieHeader =
        PluginCookieManager.instance.cookieHeader(plugin.name);
    final ua = PluginCookieManager.instance.userAgentFor(plugin.name);
    try {
      final response = await DioFactory.pluginDio.request<String>(
        url,
        options: Options(
          method: 'GET',
          responseType: ResponseType.plain,
          headers: {
            'Cookie': cookieHeader,
            if (ua.isNotEmpty) 'User-Agent': ua,
          },
        ),
      );
      final doc = html_parser.parse(response.data ?? '');
      // 未登录特征存在 → 无效
      if (cfg.xpathUnlogin.isNotEmpty && _xpathExists(doc, cfg.xpathUnlogin)) {
        return LoginCheckResult(
          valid: false,
          hasToken: true,
          message: '检测到未登录特征',
        );
      }
      // 已登录特征存在 → 有效
      if (cfg.xpath.isNotEmpty && _xpathExists(doc, cfg.xpath)) {
        return LoginCheckResult(
          valid: true,
          hasToken: true,
          message: 'XPath 特征有效',
        );
      }
      // 仅配未登录特征且其未出现 → 判定已登录
      if (cfg.xpath.isEmpty && cfg.xpathUnlogin.isNotEmpty) {
        return LoginCheckResult(
          valid: true,
          hasToken: true,
          message: '未出现未登录特征',
        );
      }
      return LoginCheckResult(
        valid: false,
        hasToken: true,
        message: 'XPath 特征未匹配',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return LoginCheckResult(
          valid: false,
          hasToken: true,
          statusCode: status,
          message: '未登录（HTTP $status）',
        );
      }
      // 网络异常：保守视为有效
      KazumiLogger().w(
        '[LoginCheckService] ${plugin.name} XPath 检测网络异常，保留登录态: ${e.message}',
      );
      return LoginCheckResult(
        valid: true,
        hasToken: true,
        statusCode: status,
        message: '网络异常，保留登录态',
      );
    } catch (e) {
      KazumiLogger().w('[LoginCheckService] ${plugin.name} XPath 检测异常: $e');
      return LoginCheckResult(
        valid: true,
        hasToken: true,
        message: '检测异常，保留登录态',
      );
    }
  }

  /// XPath 特征是否存在于文档（XPath → CSS 选择器，html 包 querySelector）。
  bool _xpathExists(html_dom.Document doc, String xpath) {
    final css = _xpathToCss(xpath);
    if (css.isEmpty) return false;
    try {
      return doc.querySelector(css) != null;
    } catch (_) {
      return false;
    }
  }

  /// 把常用 XPath（`//tag[@attr='v']`、`//tag[@attr]`、后代 `//a//b`、`//a/b`）
  /// 转换为 CSS 选择器；无法转换时返回空串（视为未匹配）。
  String _xpathToCss(String xpath) {
    var s = xpath.trim();
    if (s.isEmpty) return '';
    s = s.replaceFirst(RegExp(r'^//'), '');
    s = s.replaceAllMapped(
      RegExp(r"@([\w-]+)\s*=\s*(['\"])(.*?)\2"),
      (m) => '[${m[1]}="${m[3]}"]',
    );
    s = s.replaceAllMapped(RegExp(r'@([\w-]+)'), (m) => '[${m[1]}]');
    s = s.replaceAll('//', ' ').replaceAll('/', ' > ');
    return s.trim();
  }

  /// 替换字符串中的 token 占位符。
  String _renderTemplate(String template, String token, String placeholder) {
    if (template.isEmpty) return template;
    return template.replaceAll(placeholder, token);
  }

  /// 替换 Map 中所有字符串值的 token 占位符（URL 参数/Header）。
  Map<String, dynamic> _renderMap(
    Map<String, dynamic> source,
    String token,
    String placeholder,
  ) {
    if (source.isEmpty) return const {};
    return source.map((key, value) {
      if (value is String) {
        return MapEntry(key, value.replaceAll(placeholder, token));
      }
      return MapEntry(key, value);
    });
  }

  /// 校验响应体 `successCodePath` 处字段是否符合预期。null 表示忽略响应体。
  bool _checkCode(String? body, int? expectCode, String path) {
    if (expectCode == null) return true;
    if (body == null || body.isEmpty) return false;
    try {
      final decoded = jsonDecode(body);
      final value = _readJsonPath(decoded, path);
      return value is int && value == expectCode;
    } catch (_) {
      return false;
    }
  }

  /// 按 JSONPath（如 `$.code`、`$.data.code`）读取值；空路径回退顶层。
  dynamic _readJsonPath(dynamic root, String path) {
    if (path.isEmpty) return root;
    final normalized = path.startsWith(r'$') ? path.substring(1) : path;
    dynamic current = root;
    for (final part in normalized.split('.')) {
      final key = part.trim();
      if (key.isEmpty) continue;
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }
}

/// 🆕 剥离 token 的 `Bearer ` 前缀（部分站点 token 自带前缀，如次元城），
/// 保证规则 `Bearer @token` 拼接正确；纯 JWT 原样返回。
String _stripBearerPrefix(String token) {
  final t = token.trim();
  if (t.toLowerCase().startsWith('bearer ')) return t.substring(7).trim();
  return t;
}

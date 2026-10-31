import 'dart:convert';

import 'package:dio/dio.dart';
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

    // XPath 特征模式：服务层无法加载 WebView 检测页面特征，降级为
    // 「已保存登录态」判断（真检测在登录页 success 特征轮询）。
    if (plugin.checkConfig?.isXpath == true) {
      final valid = PluginCookieManager.instance.hasSaved(plugin.name);
      return LoginCheckResult(
        valid: valid,
        hasToken: valid,
        message: valid ? '已保存登录态' : '未保存登录态',
      );
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
      // 诊断：打印 check 实际返回，便于定位「已过期」问题。
      final respBody = response.data?.toString();
      KazumiLogger().w(
        '[LoginCheck] ${plugin.name} $url -> HTTP ${response.statusCode} '
        'body=${respBody != null && respBody.length > 300 ? respBody.substring(0, 300) : respBody} '
        'valid=$valid',
      );
      return LoginCheckResult(
        valid: valid,
        hasToken: true,
        statusCode: response.statusCode,
        message: valid ? '有效' : 'token 失效（HTTP ${response.statusCode}）',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // 诊断：打印异常响应。
      final errBody = e.response?.data?.toString();
      KazumiLogger().w(
        '[LoginCheck] ${plugin.name} $url 异常 HTTP $status '
        'body=${errBody != null && errBody.length > 300 ? errBody.substring(0, 300) : errBody}',
      );
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

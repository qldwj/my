import 'package:cookie_jar/cookie_jar.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 每条规则的 Cookie 管理器（Hive 持久化）
///
/// 为每条规则维护一个独立 CookieJar，
/// 通过 [saveFromWebView] 将 WebView 捕获的 document.cookie 字符串
/// 解析后存入对应规则的 jar，并同步写入 Hive（[GStorage.pluginCookies]），
/// **重启后仍有效**，不必重新登录。
/// 验证 Cookie 通常与 User-Agent 绑定，故同时记录 WebView 的 UA，
/// 供后续 dio 请求对齐指纹。
/// Cookie 默认有效期为 [cookieTtl]（30 天），超期视为失效，
/// 需重新登录获取。
class PluginCookieManager {
  PluginCookieManager._();
  static final PluginCookieManager instance = PluginCookieManager._();

  /// Cookie 持久化有效期：默认 30 天（超期后提示重新登录获取）。
  static const Duration cookieTtl = Duration(days: 30);

  static const String _keyPrefix = 'plugin_cookie_';

  final Map<String, CookieJar> _jars = {};
  final Map<String, String> _userAgents = {};

  CookieJar _getJar(String pluginName) {
    return _jars.putIfAbsent(pluginName, () => CookieJar());
  }

  /// 该规则是否已保存【未过期】的 Cookie
  bool hasSaved(String pluginName) {
    final data = GStorage.pluginCookies.get(_keyPrefix + pluginName);
    if (data is! Map) return false;
    final savedAt = data['savedAt'];
    if (savedAt is! int) return false;
    final age =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    return age < cookieTtl;
  }

  /// Cookie 保存时间戳（毫秒）；未保存过返回 null
  int? savedAtMs(String pluginName) {
    final data = GStorage.pluginCookies.get(_keyPrefix + pluginName);
    if (data is! Map) return null;
    final v = data['savedAt'];
    return v is int ? v : null;
  }

  /// 删除某规则的 Cookie（用户主动清除登录态时调用）
  Future<void> clear(String pluginName) async {
    _jars.remove(pluginName);
    _userAgents.remove(pluginName);
    await GStorage.pluginCookies.delete(_keyPrefix + pluginName);
  }

  Future<void> saveFromWebView(
      String pluginName, String pageUrl, String cookieString,
      {String? userAgent}) async {
    if (userAgent != null && userAgent.trim().isNotEmpty) {
      _userAgents[pluginName] = userAgent.trim();
    }
    if (cookieString.trim().isEmpty) return;
    final uri = Uri.tryParse(pageUrl);
    if (uri == null) return;

    final jar = _getJar(pluginName);
    final cookies = _parseCookieString(cookieString, uri);
    if (cookies.isEmpty) return;

    await jar.saveFromResponse(uri, cookies);

    // 🆕 Hive 持久化：存 cookie 三元组 + UA + 保存时间
    final cookieData = cookies
        .map((c) => {'name': c.name, 'value': c.value, 'domain': c.domain})
        .toList();
    await GStorage.pluginCookies.put(_keyPrefix + pluginName, {
      'cookies': cookieData,
      'userAgent': userAgent ?? _userAgents[pluginName],
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    });
    KazumiLogger().i(
        '[PluginCookieManager] Saved ${cookies.length} cookies for $pluginName (Hive, ${cookieTtl.inDays}天)');
  }

  /// 解析字符串为 [Cookie] 列表
  List<Cookie> _parseCookieString(String raw, Uri uri) {
    final cookies = <Cookie>[];
    for (final part in raw.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex <= 0) continue;
      final name = trimmed.substring(0, eqIndex).trim();
      final value = trimmed.substring(eqIndex + 1).trim();
      try {
        final cookie = Cookie(name, value)
          ..domain = uri.host
          ..path = '/';
        cookies.add(cookie);
      } catch (_) {}
    }
    return cookies;
  }

  /// 合并内存 + Hive（重启后从 Hive 恢复）；过期返回空列表
  Future<List<Cookie>> loadForRequest(
    String pluginName,
    Uri uri,
  ) async {
    final jar = _jars[pluginName];
    if (jar != null) {
      final fromMemory = await jar.loadForRequest(uri);
      if (fromMemory.isNotEmpty) return fromMemory;
    }
    // 🆕 Hive 恢复（重启后仍有效）
    final data = GStorage.pluginCookies.get(_keyPrefix + pluginName);
    if (data is! Map) return <Cookie>[];
    final savedAt = data['savedAt'];
    if (savedAt is int) {
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
      if (age >= cookieTtl) return <Cookie>[]; // 已过期
    }
    final result = <Cookie>[];
    final raw = data['cookies'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final name = item['name'];
        final value = item['value'];
        final domain = item['domain'];
        if (name is String && value is String) {
          result.add(Cookie(name, value)
            ..domain = (domain is String ? domain : uri.host)
            ..path = '/');
        }
      }
    }
    return result;
  }

  /// 验证时 WebView 使用的 User-Agent；未验证过的规则返回 null
  String? userAgentFor(String pluginName) {
    if ((_userAgents[pluginName]?.isNotEmpty ?? false)) {
      return _userAgents[pluginName];
    }
    final data = GStorage.pluginCookies.get(_keyPrefix + pluginName);
    if (data is! Map) return null;
    final ua = data['userAgent'];
    return ua is String ? ua : null;
  }
}

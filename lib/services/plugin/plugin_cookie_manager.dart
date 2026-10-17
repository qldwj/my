import 'package:cookie_jar/cookie_jar.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/storage/storage.dart';

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

  /// Cookie 有效天数（默认 1 天；紫色登录规则站点 cookie 过期快，
  /// 30 天太久，超期后一直静默失败，改 1 天尽快提示重新登录）。
  static const int _defaultTtlDays = 1;
  static const String _ttlDaysKey = 'plugin_cookie_ttl_days';

  /// 读取当前 Cookie 有效天数（默认 30）
  static int get cookieTtlDays {
    final v = GStorage.pluginCookies.get(_ttlDaysKey);
    return (v is int && v > 0) ? v : _defaultTtlDays;
  }

  /// 自定义 Cookie 有效天数并持久化（超时自动失效）
  static Future<void> setCookieTtlDays(int days) async {
    await GStorage.pluginCookies.put(_ttlDaysKey, days);
  }

  /// Cookie 持久化有效期（默认 30 天，超期后提示重新登录获取）。
  static Duration get cookieTtl => Duration(days: cookieTtlDays);

  static const String _keyPrefix = 'plugin_cookie_';

  final Map<String, CookieJar> _jars = {};
  final Map<String, String> _userAgents = {};

  CookieJar _getJar(String pluginName) {
    return _jars.putIfAbsent(pluginName, () => CookieJar());
  }

  /// 该规则是否已保存【未过期】的 Cookie
  ///
  /// 🆕 优先按 Cookie 自带真实过期时间（expiresAt）判断；
  /// 若是会话级（无 expires），则回退 TTL（默认 1 天）；
  /// 若已过期，返回 false。
  bool hasSaved(String pluginName) {
    final data = GStorage.pluginCookies.get(_keyPrefix + pluginName);
    if (data is! Map) return false;
    return _isValid(data);
  }

  /// 🆕 判断一份已存 cookie 数据是否仍在有效期
  bool _isValid(Map data) {
    final savedAt = data['savedAt'];
    if (savedAt is! int) return false;
    final expiresAt = data['expiresAt'];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (expiresAt is int) {
      // 有真实过期时间：以此为准
      return now < expiresAt;
    }
    // 会话级（无 expires）：回退固定 TTL
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    return age < cookieTtl;
  }

  /// 🆕 Cookie 状态详情（供 UI 展示：是否有效/真实过期时间/是否有缓存）
  ///
  /// 返回 Map：
  /// - hasCookie: 是否存过 cookie
  /// - valid: 是否仍有效
  /// - savedAt: 保存时间（DateTime?）
  /// - expiresAt: 真实过期时间（DateTime?，null=会话级无 expires）
  /// - isSession: 是否会话级（无 expires）
  /// - cookieCount: cookie 条数
  Map<String, dynamic> cookieStatus(String pluginName) {
    final data = GStorage.pluginCookies.get(_keyPrefix + pluginName);
    if (data is! Map) {
      return {
        'hasCookie': false,
        'valid': false,
        'savedAt': null,
        'expiresAt': null,
        'isSession': false,
        'cookieCount': 0,
      };
    }
    final savedAtMs = data['savedAt'];
    final expiresAtMs = data['expiresAt'];
    final raw = data['cookies'];
    final count = raw is List ? raw.length : 0;
    return {
      'hasCookie': true,
      'valid': _isValid(data),
      'savedAt': savedAtMs is int
          ? DateTime.fromMillisecondsSinceEpoch(savedAtMs)
          : null,
      'expiresAt': expiresAtMs is int
          ? DateTime.fromMillisecondsSinceEpoch(expiresAtMs)
          : null,
      'isSession': expiresAtMs is! int,
      'cookieCount': count,
    };
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

  /// 清除所有已保存的 Cookie（一键清理误判的登录态）
  Future<void> clearAll() async {
    final keys = GStorage.pluginCookies.keys.toList();
    for (final key in keys) {
      if (key is String && key.startsWith(_keyPrefix)) {
        await GStorage.pluginCookies.delete(key);
      }
    }
    _jars.clear();
    _userAgents.clear();
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
    final parsed = _parseCookieString(cookieString, uri);
    final cookies = parsed.cookies;
    if (cookies.isEmpty) return;

    await jar.saveFromResponse(uri, cookies);

    // 🆕 Hive 持久化：存 cookie 三元组 + UA + 保存时间 + 真实过期时间
    final cookieData = cookies
        .map((c) => {'name': c.name, 'value': c.value, 'domain': c.domain})
        .toList();
    await GStorage.pluginCookies.put(_keyPrefix + pluginName, {
      'cookies': cookieData,
      'userAgent': userAgent ?? _userAgents[pluginName],
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      // 🆕 真实过期时间（毫秒）；null 表示该站 cookie 无 expires（会话级）
      'expiresAt': parsed.latestExpiryMs,
    });
    KazumiLogger().i(
        '[PluginCookieManager] Saved ${cookies.length} cookies for $pluginName '
        '(Hive, 真实过期=${parsed.latestExpiryMs == null ? '无(会话级)' : DateTime.fromMillisecondsSinceEpoch(parsed.latestExpiryMs!)})');
  }

  /// 解析字符串为 cookie 列表，并提取真实过期时间
  ({List<Cookie> cookies, int? latestExpiryMs}) _parseCookieString(
      String raw, Uri uri) {
    final cookies = <Cookie>[];
    int? maxAgeMs;
    String? expiresStr;
    for (final part in raw.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex <= 0) continue;
      final name = trimmed.substring(0, eqIndex).trim();
      final value = trimmed.substring(eqIndex + 1).trim();
      final lower = name.toLowerCase();
      // 🆕 提取 cookie 元属性（用于真实过期判定）
      if (lower == 'max-age') {
        final secs = int.tryParse(value);
        if (secs != null && secs > 0) {
          maxAgeMs = DateTime.now()
              .add(Duration(seconds: secs))
              .millisecondsSinceEpoch;
        }
        continue;
      }
      if (lower == 'expires') {
        expiresStr = value;
        continue;
      }
      if (lower == 'path' ||
          lower == 'domain' ||
          lower == 'samesite' ||
          lower == 'secure' ||
          lower == 'httponly') {
        continue;
      }
      try {
        final cookie = Cookie(name, value)
          ..domain = uri.host
          ..path = '/';
        cookies.add(cookie);
      } catch (_) {}
    }
    // 优先用 max-age；否则解析 expires（RFC 1123 格式）
    int? latestExpiryMs = maxAgeMs;
    if (latestExpiryMs == null && expiresStr != null) {
      final dt = _parseHttpDate(expiresStr);
      latestExpiryMs = dt?.millisecondsSinceEpoch;
    }
    return (cookies: cookies, latestExpiryMs: latestExpiryMs);
  }

  /// 解析 HTTP 日期（如 Wed, 21 Oct 2026 07:28:00 GMT）
  DateTime? _parseHttpDate(String s) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    // 去掉 "Wed, " 前缀，按空格拆
    final cleaned = s.replaceAll(',', ' ').trim();
    final parts = cleaned.split(RegExp(r'\s+'));
    // 期望：[weekday] dd Mon yyyy HH:mm:ss GMT
    for (var i = 0; i < parts.length - 4; i++) {
      final day = int.tryParse(parts[i]);
      final mon = months[parts[i + 1].toLowerCase()];
      final year = int.tryParse(parts[i + 2]);
      if (day != null && mon != null && year != null && parts[i + 3].contains(':')) {
        final time = parts[i + 3].split(':');
        final hh = int.tryParse(time[0]) ?? 0;
        final mm = time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0;
        final ss = time.length > 2 ? int.tryParse(time[2]) ?? 0 : 0;
        try {
          return DateTime.utc(year, mon, day, hh, mm, ss);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
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
    if (!_isValid(data)) return <Cookie>[]; // 已过期（按真实 expires）
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

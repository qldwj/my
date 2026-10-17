/// Set-Cookie 响应头解析
///
/// 用于登录 POST 请求后，从 Response Header 的 `Set-Cookie` 中提取
/// name / value / max-age / expires，并计算 Cookie 的真实到期时间。
///
/// 规则（RFC 6265）：
/// - 到期时间优先使用 `Max-Age`（秒，相对当前时间）
/// - `Max-Age` 不存在时才使用 `Expires`（GMT 绝对时间）
/// - 两者都不存在 → 会话 Cookie（Session Cookie），关闭浏览器即失效
class SetCookieInfo {
  const SetCookieInfo({
    required this.name,
    required this.value,
    this.maxAge,
    this.expiresRaw,
    this.expiresAt,
    required this.isSession,
    this.path,
    this.domain,
    this.secure = false,
    this.httpOnly = false,
  });

  /// Cookie 名（Set-Cookie 第一个 `name=value` 的 name）
  final String name;

  /// Cookie 值（可能包含 `=`）
  final String value;

  /// Max-Age 原始值（秒），仅当 Set-Cookie 中显式存在且可解析时非空
  final int? maxAge;

  /// Expires 原始字符串（未解析），便于排查
  final String? expiresRaw;

  /// 解析出的绝对到期时间（UTC）
  /// - 有 Max-Age：now + maxAge 秒
  /// - 否则有 Expires：解析出的 GMT 时间
  /// - 两者都无：null（会话 Cookie）
  final DateTime? expiresAt;

  /// 是否为会话 Cookie（无 Max-Age 且无 Expires）
  final bool isSession;

  final String? path;
  final String? domain;
  final bool secure;
  final bool httpOnly;

  /// 是否已过期（会话 Cookie 永远视为未过期）
  bool isExpiredAt(DateTime now) {
    final at = expiresAt;
    if (at == null) return false;
    return now.toUtc().isAfter(at.toUtc());
  }

  @override
  String toString() {
    return 'SetCookieInfo(name: $name, value: $value, maxAge: $maxAge, '
        'expiresRaw: $expiresRaw, expiresAt: ${expiresAt?.toIso8601String()}, '
        'isSession: $isSession, path: $path, domain: $domain, '
        'secure: $secure, httpOnly: $httpOnly)';
  }
}

/// 解析单条 Set-Cookie
///
/// [raw] 原始 Set-Cookie 头值，例如：
/// `session=abc123; Path=/; Max-Age=3600; HttpOnly; Secure`
/// 或 `sid=xyz; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/`
///
/// [now] 用于计算 Max-Age 的当前时间，默认 `DateTime.now()`（便于测试注入）。
///
/// 解析失败时返回 null（如空串、缺少 `name=`）。
SetCookieInfo? parseSetCookie(String raw, {DateTime? now}) {
  final input = raw.trim();
  if (input.isEmpty) return null;

  final segments = input.split(';');

  // ── 1) 第一段是 name=value（value 可能包含 '='，只按第一个 '=' 切分）
  final first = segments.first.trim();
  final eq = first.indexOf('=');
  if (eq <= 0) return null;
  final name = first.substring(0, eq).trim();
  final value = first.substring(eq + 1).trim();
  if (name.isEmpty) return null;

  // ── 2) 解析属性
  int? maxAge;
  String? expiresRaw;
  DateTime? expiresAt;
  String? path;
  String? domain;
  bool secure = false;
  bool httpOnly = false;

  for (var i = 1; i < segments.length; i++) {
    final seg = segments[i].trim();
    if (seg.isEmpty) continue;
    final idx = seg.indexOf('=');
    final key = (idx >= 0 ? seg.substring(0, idx) : seg).trim().toLowerCase();
    final val = idx >= 0 ? seg.substring(idx + 1).trim() : '';

    switch (key) {
      case 'max-age':
        // Max-Age 取整数秒；非法（非数字）时忽略
        maxAge = int.tryParse(val);
        break;
      case 'expires':
        expiresRaw = val;
        expiresAt = parseHttpDate(val);
        break;
      case 'path':
        path = val;
        break;
      case 'domain':
        domain = val;
        break;
      case 'secure':
        secure = true;
        break;
      case 'httponly':
        httpOnly = true;
        break;
      default:
        // SameSite / Priority 等其余属性忽略
        break;
    }
  }

  // ── 3) 计算真实到期时间：Max-Age 优先，其次 Expires，都无 → 会话 Cookie
  final current = (now ?? DateTime.now()).toUtc();
  DateTime? effectiveExpiry;
  if (maxAge != null) {
    effectiveExpiry = current.add(Duration(seconds: maxAge));
  } else if (expiresAt != null) {
    effectiveExpiry = expiresAt.toUtc();
  }

  return SetCookieInfo(
    name: name,
    value: value,
    maxAge: maxAge,
    expiresRaw: expiresRaw,
    expiresAt: effectiveExpiry,
    isSession: effectiveExpiry == null,
    path: path,
    domain: domain,
    secure: secure,
    httpOnly: httpOnly,
  );
}

/// 批量解析多条 Set-Cookie（HTTP 响应头 `set-cookie` 可能有多条）
///
/// Dart 中获取方式：
/// ```dart
/// final rawCookies = response.headers[HttpHeaders.setCookieHeader]; // List<String>?
/// final list = parseSetCookies(rawCookies);
/// ```
///
/// 解析失败的条目会被跳过（不会抛异常）。
List<SetCookieInfo> parseSetCookies(Iterable<String>? rawHeaders,
    {DateTime? now}) {
  if (rawHeaders == null) return const [];
  final result = <SetCookieInfo>[];
  for (final raw in rawHeaders) {
    final info = parseSetCookie(raw, now: now);
    if (info != null) result.add(info);
  }
  return result;
}

/// 从一批 Set-Cookie 中挑出「登录态」Cookie（按名字关键词）
///
/// 常见登录态键名：token / session / sid / auth / jwt / access_token …
/// 若没有匹配，返回整批中最晚到期的那个（会话 Cookie 视为最晚）。
SetCookieInfo? pickAuthCookie(List<SetCookieInfo> cookies) {
  if (cookies.isEmpty) return null;
  const keywords = [
    'token', 'session', 'sid', 'auth', 'jwt', 'access', 'refresh', 'login'
  ];
  for (final c in cookies) {
    final lower = c.name.toLowerCase();
    if (keywords.any(lower.contains)) return c;
  }
  // 回退：最晚到期的（会话 Cookie 优先视为最晚）
  cookies.sort((a, b) {
    final ea = a.expiresAt;
    final eb = b.expiresAt;
    if (ea == null && eb == null) return 0;
    if (ea == null) return -1;
    if (eb == null) return 1;
    return eb.compareTo(ea);
  });
  return cookies.first;
}

/// 解析 HTTP 日期（RFC 1123 / RFC 850 / asctime），统一按 GMT(UTC) 处理
///
/// 支持格式示例：
/// - `Wed, 21 Oct 2026 07:28:00 GMT`（RFC 1123，最常见）
/// - `Wednesday, 21-Oct-26 07:28:00 GMT`（RFC 850）
/// - `Wed Oct 21 07:28:00 2026`（asctime）
///
/// 解析失败返回 null（不抛异常）。
DateTime? parseHttpDate(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;

  // 去掉星期前缀（Wed, / Wednesday,）
  final withoutWeekday = s.replaceFirst(RegExp(r'^[A-Za-z]+,\s*'), '');
  // 统一分隔符：'-' ',' 以及连续空白都换成单空格
  final normalized =
      withoutWeekday.replaceAll(RegExp(r'[-,\s]+'), ' ').trim();

  const months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  int? day;
  int? month;
  int? year;
  int? hour;
  int? minute;
  int? second;

  // 按 token 形状精确识别，而不是"谁先空谁占位"：
  // - 含 ':'            → 时间 HH:mm:ss
  // - 3 个字母且是月份    → 月份
  // - 纯数字 4 位         → 年份
  // - 纯数字 1~2 位       → 日期或两位年份（由后续是否已有年份决定）
  for (final token in normalized.split(' ')) {
    if (token.isEmpty) continue;

    if (token.contains(':')) {
      final tp = token.split(':');
      if (tp.length >= 3) {
        hour = int.tryParse(tp[0]);
        minute = int.tryParse(tp[1]);
        second = int.tryParse(tp[2].split('.').first);
      }
      continue;
    }

    if (token.length >= 3 && RegExp(r'^[A-Za-z]+$').hasMatch(token)) {
      final m = months[token.toLowerCase().substring(0, 3)];
      if (m != null) {
        month = m;
        continue;
      }
      // 其他单词（GMT/UTC 等）忽略
      continue;
    }

    if (RegExp(r'^\d+$').hasMatch(token)) {
      final n = int.parse(token);
      if (token.length >= 4) {
        year = n; // 4 位一定是年份
      } else if (token.length == 2 && year != null) {
        // 已有 4 位年份时，2 位数字只能是日期
        day ??= n;
      } else if (token.length == 2 && year == null && day != null) {
        // RFC 850：先有日期后有两位年份（21-Oct-26）
        year = n < 70 ? 2000 + n : 1900 + n;
      } else if (token.length == 2) {
        // 尚未确定：先当日期（RFC 1123 中日期在年份之前）
        day ??= n;
      } else {
        // 1 位数字：日期
        day ??= n;
      }
      continue;
    }
  }

  if (day == null ||
      month == null ||
      year == null ||
      hour == null ||
      minute == null ||
      second == null) {
    return null;
  }

  // GMT → UTC。用 DateTime.utc 保证不受本地时区影响
  try {
    final dt = DateTime.utc(year, month, day, hour, minute, second);
    // 回校验：避免 2 月 30 日被自动进位成 3 月 2 日
    if (dt.year != year || dt.month != month || dt.day != day) return null;
    return dt;
  } catch (_) {
    return null;
  }
}

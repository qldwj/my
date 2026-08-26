
/// 樱花动漫扫码登录协议解析
class YhdmgzQrProtocol {
  static const String scheme = 'yhdm';

  /// 提取二维码中的会话码。
  /// 兼容 `?token=xxx` 与 `?code=xxx` 两种写法。
  static String? getToken(String value) {
    try {
      final uri = Uri.parse(value);
      if (uri.scheme != scheme || uri.host != 'login') return null;

      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) return token;

      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) return code;

      return null;
    } catch (_) {
      return null;
    }
  }

  static bool isLoginQr(String value) => getToken(value) != null;
}

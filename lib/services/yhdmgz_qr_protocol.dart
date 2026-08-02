
/// 樱花动漫扫码登录协议解析
class YhdmgzQrProtocol {
  static const String scheme = 'yhdmgz';

  static String? getToken(String value) {
    try {
      final uri = Uri.parse(value);
      if (uri.scheme != scheme || uri.host != 'login') return null;
      return uri.queryParameters['token'];
    } catch (_) {
      return null;
    }
  }

  static bool isLoginQr(String value) => getToken(value) != null;
}

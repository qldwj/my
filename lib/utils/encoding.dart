import 'dart:convert';

/// 将 JSON 编码为 yhdmgz 协议链接（用于 App 内部）
String jsonToKazumiBase64(String jsonStr) {
  final base64Str = base64Encode(utf8.encode(jsonStr));
  return 'yhdmgz://$base64Str';
}

/// 生成可分享的 HTTP 链接（用于分享给好友）
/// 格式: https://qlyyz.xyz/share?gz=<base64>
String jsonToShareUrl(String jsonStr) {
  final base64Str = base64Encode(utf8.encode(jsonStr));
  return 'https://qlyyz.xyz/share?gz=$base64Str';
}

/// 从 yhdmgz、kazumi 或 http 链接解码 JSON
/// 支持:
///   - yhdmgz://<base64>
///   - kazumi://<base64>
///   - https://qlyyz.xyz/share?gz=<base64>
String kazumiBase64ToJson(String input) {
  final trimmed = input.trim();
  
  // 匹配 https://qlyyz.xyz/share?gz= 格式
  final httpMatch = RegExp(
    r'^https?://[^/]+/share\?gz=(?<payload>[A-Za-z0-9+/=_-]+)',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (httpMatch != null) {
    var payload = httpMatch.namedGroup('payload') ?? '';
    final normalized = base64.normalize(
      payload.replaceAll('-', '+').replaceAll('_', '/'),
    );
    try {
      return utf8.decode(base64.decode(normalized));
    } on FormatException {
      throw const FormatException('规则链接内容无效');
    }
  }

  // 匹配 yhdmgz:// 或 kazumi://
  final schemeMatch = RegExp(
    r'^(yhdmgz|kazumi):(?://)?',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (schemeMatch == null) {
    throw const FormatException('无效的规则链接');
  }

  var payload = trimmed.substring(schemeMatch.end);
  try {
    payload = Uri.decodeComponent(payload);
  } on FormatException {
    throw const FormatException('规则链接编码无效');
  }
  payload = payload.replaceAll(RegExp(r'\s'), '');
  if (payload.isEmpty) {
    throw const FormatException('规则链接为空');
  }

  final normalized = base64.normalize(
    payload.replaceAll('-', '+').replaceAll('_', '/'),
  );
  try {
    return utf8.decode(base64.decode(normalized));
  } on FormatException {
    throw const FormatException('规则链接内容无效');
  }
}

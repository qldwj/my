import 'dart:convert';

/// 将 JSON 编码为 yhdmgz 协议链接
String jsonToKazumiBase64(String jsonStr) {
  final base64Str = base64Encode(utf8.encode(jsonStr));
  return 'yhdmgz://$base64Str';
}

/// 从 yhdmgz 或 kazumi 协议链接解码 JSON
/// 支持 yhdmgz:// 和 kazumi:// 两种格式
String kazumiBase64ToJson(String input) {
  final trimmed = input.trim();
  
  // 匹配 yhdmgz:// 或 kazumi://
  final schemeMatch = RegExp(
    r'^(yhdmgz|kazumi):(?://)?',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (schemeMatch == null) {
    throw const FormatException('无效的规则链接，请使用 yhdmgz:// 格式');
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

  // 处理 Base64，兼容 URL-safe 格式
  final normalized = base64.normalize(
    payload.replaceAll('-', '+').replaceAll('_', '/'),
  );
  try {
    return utf8.decode(base64.decode(normalized));
  } on FormatException {
    throw const FormatException('规则链接内容无效');
  }
}

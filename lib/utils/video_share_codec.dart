import 'dart:convert';
import 'dart:io';

/// 视频分享链接编解码
///
/// 加密流程（对应站点 `https://qlyyz.xyz/video?url=...` 的 PHP 解密逻辑）：
/// 1. 原始地址（UTF-8）做 `gzdeflate($str, 9)` 等价处理：
///    raw DEFLATE 压缩，最高压缩级别（无 zlib 头，PHP 用 gzinflate 解压）；
/// 2. 压缩后的二进制做 RFC4648 Base32 编码，字母表只用
///    `ABCDEFGHIJKLMNOPQRSTUVWXYZ234567`，去掉末尾 `=` 填充；
/// 3. 结果只有大写字母与数字 2-7，无需 URL 转义，直接拼到分享链接。
///
/// PHP 侧解密：
/// ```php
/// $data = gzinflate(base32_decode($_GET['url']));
/// ```
class VideoShareCodec {
  /// 分享页地址，密文通过 `url` 参数传递
  static const String shareOrigin = 'https://qlyyz.xyz/video';

  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// 生成分享链接：`https://qlyyz.xyz/video?url=<密文>`
  static String buildShareLink(String videoUrl) =>
      '$shareOrigin?url=${encode(videoUrl)}';

  /// gzdeflate(url, 9) + Base32（无填充）
  static String encode(String text) =>
      base32Encode(_deflate(utf8.encode(text)));

  /// 反向解密：Base32 解码 + gzinflate（供本机校验/调试使用）
  static String decode(String encoded) =>
      utf8.decode(_inflate(base32Decode(encoded)));

  /// raw DEFLATE 压缩（对应 PHP `gzdeflate($str, 9)`）
  static List<int> _deflate(List<int> input) =>
      ZLibCodec(level: 9, raw: true).encode(input);

  /// raw DEFLATE 解压（对应 PHP `gzinflate($str)`）
  static List<int> _inflate(List<int> input) =>
      ZLibCodec(raw: true).decode(input);

  /// RFC4648 Base32 编码（大写，去掉 `=` 填充）
  static String base32Encode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final buffer = StringBuffer();
    var bits = 0;
    var value = 0;
    for (final byte in bytes) {
      value = ((value << 8) | (byte & 0xff)) & 0xffffffff;
      bits += 8;
      while (bits >= 5) {
        buffer.write(_alphabet[(value >> (bits - 5)) & 0x1f]);
        bits -= 5;
      }
    }
    if (bits > 0) {
      buffer.write(_alphabet[(value << (5 - bits)) & 0x1f]);
    }
    return buffer.toString();
  }

  /// RFC4648 Base32 解码（忽略 `=` 填充与非法字符）
  static List<int> base32Decode(String encoded) {
    final output = <int>[];
    var bits = 0;
    var value = 0;
    for (final unit in encoded.toUpperCase().codeUnits) {
      final index = _alphabet.indexOf(String.fromCharCode(unit));
      if (index < 0) continue;
      value = ((value << 5) | index) & 0xffffffff;
      bits += 5;
      if (bits >= 8) {
        output.add((value >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    return output;
  }
}

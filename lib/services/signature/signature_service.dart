import 'dart:io';
import 'package:flutter/services.dart';

/// 应用签名校验。
///
/// 仅 Android 生效。通过 Flutter 层 MethodChannel 拿到 APK 签名证书的 SHA-256，
/// 与构建时 --dart-define 注入的 [EXPECTED_SIGNATURE_SHA256] 比对。
///
/// 因为校验逻辑写在 Flutter（编译后难改）：若篡改过 Dart 代码，必须重新编译打包，
/// 就会改变签名 → 校验必然失败，篡改方无法再隐藏。
///
/// 开启方式（发布构建）：
///   flutter build apk --dart-define=SIGNATURE_CHECK=true \
///                    --dart-define=EXPECTED_SIGNATURE_SHA256=<小写十六进制>
class SignatureService {
  /// 构建时开关：SIGNATURE_CHECK = true 才开启校验
  static const bool checkEnabled =
      bool.fromEnvironment('SIGNATURE_CHECK', defaultValue: false);

  /// 构建时注入的期望 SHA-256 指纹（小写十六进制，无冒号）
  static const String expectedSha256 =
      String.fromEnvironment('EXPECTED_SIGNATURE_SHA256');

  static const MethodChannel _channel =
      MethodChannel('com.predidit.kazumi/signature');

  /// 返回 `true` 表示校验通过，或校验未启用。
  /// 返回 `false` 表示签名不合法。
  static Future<bool> verify() async {
    if (!checkEnabled) return true; // 未开启 → 直接放行（开发构建）
    if (!Platform.isAndroid) return true; // 仅 Android 校验
    if (expectedSha256.isEmpty) return false; // 开启但未配期望值 → 不合法

    final String actual;
    try {
      actual =
          (await _channel.invokeMethod<String>('getSigningCertSha256')) ?? '';
    } catch (_) {
      return false; // 无法取得签名 → 不合法
    }

    final expected = expectedSha256.trim().toLowerCase();
    return actual
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .any((s) => s == expected);
  }
}

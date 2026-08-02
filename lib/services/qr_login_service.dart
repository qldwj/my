
import 'package:flutter/material.dart';

/// 樱花动漫扫码登录协议
/// 格式: yhdmgz://login?token=xxxx
class QrLoginService {
  static const String scheme = "yhdmgz";

  static bool canHandle(String value) {
    return value.startsWith("$scheme://login");
  }

  static String? getToken(String value) {
    try {
      final uri = Uri.parse(value);
      return uri.queryParameters["token"];
    } catch (_) {
      return null;
    }
  }

  static Future<bool> confirmLogin(
      BuildContext context, String token) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("扫码登录"),
        content: const Text("是否允许该设备登录樱花动漫账号？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("确认登录"),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}


import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/services/auth_service.dart';

/// 樱花动漫扫码登录
/// 只处理 yhdmgz://login，不影响规则导入
class QrLoginService {
  static const String scheme = "yhdmgz";

  static bool canHandle(String value) {
    try {
      final uri = Uri.parse(value);
      return uri.scheme == scheme && uri.host == "login";
    } catch (_) {
      return false;
    }
  }

  static String? getToken(String value) {
    try {
      final uri = Uri.parse(value);
      if (uri.scheme != scheme || uri.host != "login") return null;
      return uri.queryParameters["token"] ?? uri.queryParameters["code"];
    } catch (_) {
      return null;
    }
  }

  /// 扫码端确认登录
  static Future<bool> confirmLogin(
      BuildContext context, String token) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("扫码登录"),
        content: const Text("是否允许此设备登录樱花动漫账号？"),
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

    if (ok != true) return false;

    // 关键修复：
    // 原代码只关闭弹窗，没有通知服务器，
    // 导致被登录设备一直轮询转圈。
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('${AuthService.baseUrl}?action=qrcode_confirm'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        "token": token,
        "confirm": true,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(body);
      return data["success"] == true || data["status"] == "confirmed";
    } catch (_) {
      return false;
    }
  }
}

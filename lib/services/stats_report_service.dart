import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../services/sync/history_sync_service.dart';

/// 启动上报统计：每次 App 启动向服务器上报一次（设备码 + 手机型号 + IP）
/// 后端：qlyyz.xyz/api/v1/checkin.php?action=stats_post
class StatsReportService {
  static const String _url =
      'https://qlyyz.xyz/api/v1/checkin.php?action=stats_post';

  /// 启动时调用，异步、失败静默，不阻塞启动流程
  static Future<void> reportStartup() async {
    try {
      final deviceId = await HistorySyncService().getDeviceId();
      final model = await _deviceModel();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.postUrl(Uri.parse(_url));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({'device_id': deviceId, 'model': model})));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain();
      client.close();
    } catch (_) {
      // 静默失败：不影响 App 启动
    }
  }

  static Future<String> _deviceModel() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final b = '${a.brand} ${a.model}'.trim();
        return b.isEmpty ? (a.device ?? '') : b;
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        return i.model ?? '';
      }
    } catch (_) {}
    return '';
  }
}

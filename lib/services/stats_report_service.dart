import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../services/sync/history_sync_service.dart';

/// 启动上报统计：每次 App 启动向服务器上报一次（设备码 + 手机型号 + 精确公网 IP）
/// 后端：qlyyz.xyz/api/v1/checkin.php?action=stats_post
class StatsReportService {
  static const String _url =
      'https://qlyyz.xyz/api/v1/checkin.php?action=stats_post';

  /// 启动时调用，异步、失败静默，不阻塞启动流程
  static Future<void> reportStartup() async {
    try {
      final deviceId = await HistorySyncService().getDeviceId();
      final model = await _deviceModel();
      final publicIp = await _publicIp();
      final client =
          HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.postUrl(Uri.parse(_url));
      req.headers.contentType = ContentType.json;
      if (publicIp.isNotEmpty) {
        // 精确公网 IP 放请求头，服务器优先采用
        req.headers.set('X-Real-IP', publicIp);
      }
      req.add(utf8.encode(jsonEncode({
        'device_id': deviceId,
        'model': model,
        'ip': publicIp,
      })));
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain();
      client.close();
    } catch (_) {
      // 静默失败：不影响 App 启动
    }
  }

  /// 设备型号
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

  /// 获取精确公网 IP（多个 IP 服务依次 fallback）
  static Future<String> _publicIp() async {
    const candidates = <String>[
      'https://api.ipify.org?format=json',
      'https://ip.sb/json',
      'https://ifconfig.me/ip',
    ];
    for (final url in candidates) {
      try {
        final c = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4);
        final req = await c.getUrl(Uri.parse(url));
        final res = await req.close().timeout(const Duration(seconds: 4));
        final body = await res.transform(utf8.decoder).join();
        c.close();
        if (url.contains('ifconfig')) {
          final ip = body.trim();
          if (ip.isNotEmpty) return ip;
        } else {
          final j = jsonDecode(body);
          final ip = (j is Map && j['ip'] != null) ? j['ip'].toString() : '';
          if (ip.isNotEmpty) return ip;
        }
      } catch (_) {}
    }
    return '';
  }
}

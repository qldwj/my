import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 局域网快速互传：点对点传输收藏与进度，不依赖公网
/// 樱花动漫粉红主题（Color(0xffEC407A)）
class LanSharePage extends StatefulWidget {
  const LanSharePage({super.key});

  @override
  State<LanSharePage> createState() => _LanSharePageState();
}

class _LanSharePageState extends State<LanSharePage> {
  static const int _port = 51234;
  HttpServer? _server;
  bool _running = false;
  bool _starting = false;
  String _ip = '';
  String _status = '';

  static const Color _sakuraPink = Color(0xffEC407A);

  @override
  void initState() {
    super.initState();
    _loadLocalIp();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  Future<void> _loadLocalIp() async {
    String? fallback;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final i in interfaces) {
        final name = (i.name ?? '').toLowerCase();
        // 跳过隧道/VPN/蜂窝虚拟接口（地址通常不可被局域网内其他设备访问）
        final isTunnel = name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('ppp') ||
            name.startsWith('wg') ||
            name.startsWith('vpn') ||
            name.startsWith('utun') ||
            name.startsWith('rmnet') ||
            name.startsWith('sw');
        for (final a in i.addresses) {
          if (a.isLoopback) continue;
          fallback ??= a.address;
          // 优先选局域网私网地址（192.168.x / 10.x / 172.16-31.x）
          if (_isPrivateLan(a.address)) {
            _ip = a.address;
            if (mounted) setState(() {});
            return;
          }
        }
        if (isTunnel) continue;
      }
    } catch (e) {
      KazumiLogger().w('LanShare: 获取本机IP失败 $e');
    }
    _ip = fallback ?? '';
    if (mounted) setState(() {});
  }

  /// 判断是否为可被局域网内其他设备直连的私网 IPv4 地址。
  bool _isPrivateLan(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final b = int.tryParse(parts[1]);
        if (b != null && b >= 16 && b <= 31) return true;
      }
    }
    return false;
  }

  String _url() => 'http://$_ip:$_port';

  // ==================== 数据导出 ====================
  Map<String, dynamic> _buildExportJson() {
    List<Map<String, dynamic>> collect = [];
    List<Map<String, dynamic>> histories = [];
    try {
      final cr = CollectCrudRepository();
      collect = cr.getAllCollectibles().map((c) {
        return {
          'type': c.type,
          'time': c.time.millisecondsSinceEpoch,
          'bangumiItem': jsonEncode(c.bangumiItem),
        };
      }).toList();
    } catch (e) {
      KazumiLogger().w('LanShare: 收藏导出失败 $e');
    }
    try {
      final hr = HistoryRepository();
      histories = hr.getAllHistories().map((h) {
        final prog = <String, Map<String, dynamic>>{};
        h.progresses.forEach((ep, p) {
          prog['$ep'] = {
            'episode': p.episode,
            'road': p.road,
            'progressMs': p.progress.inMilliseconds,
            'updatedAtMs': p.updatedAtMs,
          };
        });
        return {
          'adapterName': h.adapterName,
          'lastWatchEpisode': h.lastWatchEpisode,
          'lastWatchTime': h.lastWatchTime.millisecondsSinceEpoch,
          'lastSrc': h.lastSrc,
          'lastWatchEpisodeName': h.lastWatchEpisodeName,
          'entryKind': h.entryKind,
          'episodePageUrl': h.episodePageUrl,
          'bangumiItem': jsonEncode(h.bangumiItem),
          'progresses': prog,
        };
      }).toList();
    } catch (e) {
      KazumiLogger().w('LanShare: 历史导出失败 $e');
    }
    return {
      'app': 'cyc',
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'collect': collect,
      'histories': histories,
    };
  }

  // ==================== 数据导入 ====================
  Future<Map<String, int>> _importJson(String body) async {
    int collectOk = 0;
    int historyOk = 0;
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        return {'collect': 0, 'history': 0};
      }
      // 收藏
      final collects = json['collect'];
      if (collects is List) {
        final cr = CollectCrudRepository();
        for (final c in collects.whereType<Map>()) {
          try {
            final item = BangumiItem.fromJson(
              Map<String, dynamic>.from(jsonDecode(
                (c['bangumiItem'] ?? '').toString(),
              ) as Map),
            );
            await cr.addCollectible(item, (c['type'] as num?)?.toInt() ?? 1);
            collectOk++;
          } catch (_) {}
        }
      }
      // 历史
      final histories = json['histories'];
      if (histories is List) {
        final hr = HistoryRepository();
        for (final h in histories.whereType<Map>()) {
          try {
            final item = BangumiItem.fromJson(
              Map<String, dynamic>.from(jsonDecode(
                (h['bangumiItem'] ?? '').toString(),
              ) as Map),
            );
            final adapter = (h['adapterName'] ?? '').toString();
            final progs = h['progresses'];
            if (progs is Map) {
              progs.forEach((epKey, pv) {
                if (pv is Map) {
                  hr.updateHistory(
                    identity: PlaybackHistoryIdentity(
                      bangumiItem: item,
                      pluginName: adapter,
                      episodeNumber: (epKey as num).toInt(),
                      episodeTitle: (h['lastWatchEpisodeName'] ?? '').toString(),
                      road: (pv['road'] as num?)?.toInt() ?? 0,
                      entryKind: (h['entryKind'] ?? HistoryEntryKind.online).toString(),
                      episodePageUrl: (h['episodePageUrl'] ?? '').toString(),
                    ),
                    progress: Duration(
                      milliseconds: (pv['progressMs'] as num?)?.toInt() ?? 0,
                    ),
                  );
                }
              });
            }
            historyOk++;
          } catch (_) {}
        }
      }
    } catch (e) {
      KazumiLogger().w('LanShare: 导入失败 $e');
    }
    return {'collect': collectOk, 'history': historyOk};
  }

  // ==================== HTTP 服务 ====================
  Future<void> _startServer() async {
    if (_running || _starting) return;
    setState(() {
      _starting = true;
      _status = '正在启动…';
    });
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _server = server;
      server.listen((req) => _handle(req));
      setState(() {
        _running = true;
        _status = '已开启：$_url()';
      });
    } catch (e) {
      setState(() => _status = '启动失败：$e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopServer() async {
    await _server?.close(force: true);
    _server = null;
    if (mounted) setState(() {
      _running = false;
      _status = '已关闭';
    });
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path == '/export') {
        req.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        req.response.add(utf8.encode(jsonEncode(_buildExportJson())));
        await req.response.close();
        return;
      }
      if (path == '/import' && req.method == 'POST') {
        final body = await utf8.decodeStream(req);
        final result = await _importJson(body);
        req.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        req.response.write(jsonEncode({
          'ok': true,
          'collect': result['collect'],
          'history': result['history'],
        }));
        await req.response.close();
        return;
      }
      // 默认网页
      req.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      req.response.write(_buildHtml());
      await req.response.close();
    } catch (e) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.write('error: $e');
        await req.response.close();
      } catch (_) {}
    }
  }

  String _buildHtml() {
    return '''<!DOCTYPE html>
<html lang="zh">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>樱花动漫 · 局域网互传</title>
<style>
body{font-family:-apple-system,sans-serif;background:#fff0f3;margin:0;padding:24px;color:#333}
.card{background:#fff;border-radius:16px;padding:20px;max-width:520px;margin:0 auto;box-shadow:0 2px 12px rgba(236,64,122,.12)}
h1{color:#EC407A;font-size:20px;margin:0 0 6px}
p{font-size:14px;color:#666;margin:4px 0}
a.btn{display:inline-block;margin:14px 0 6px;padding:12px 20px;background:#EC407A;color:#fff;border-radius:12px;text-decoration:none;font-weight:600}
input[type=file]{margin-top:10px;width:100%;padding:8px;border:1px dashed #EC407A;border-radius:10px}
.msg{font-size:12px;color:#999;margin-top:6px}
</style></head>
<body><div class="card">
<h1>🌸 樱花动漫 · 局域网互传</h1>
<p>把收藏和观看进度下载成文件，发给另一台设备后，在那边用 App 的「局域网互传」上传导入。</p>
<a class="btn" href="/export">⬇ 下载数据（收藏+进度）</a>
<p class="msg">对方设备在浏览器打开此地址，下载这个文件，然后在其 App 内导入即可。</p>
<form id="f"><input type="file" id="file" accept=".json"></form>
<p class="msg" id="tip"></p>
</div>
<script>
document.getElementById('file').addEventListener('change', async function(e){
  const file=e.target.files[0]; if(!file) return;
  const text=await file.text();
  const r=await fetch('/import',{method:'POST',body:text});
  const j=await r.json();
  document.getElementById('tip').textContent='导入成功：收藏 '+j.collect+' 条，进度 '+j.history+' 条';
});
</script></body></html>''';
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _sakuraPink,
          brightness: Theme.of(context).brightness,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('局域网快速互传'),
          backgroundColor: _sakuraPink,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              icon: Icons.wifi_tethering_rounded,
              title: '发送给其他设备',
              desc: '开启后生成二维码和地址，对方浏览器打开即可下载收藏与进度。',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_running ? '共享中' : '点击开启共享'),
                    value: _running,
                    onChanged: _starting ? null : (_) {
                      if (_running) {
                        _stopServer();
                      } else {
                        _startServer();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_running && _ip.isNotEmpty) ...[
                    Text('地址：$_url()',
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 12),
                    QrImageView(
                      data: _url(),
                      version: QrVersions.auto,
                      size: 200,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.circle,
                        color: _sakuraPink,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xff333333),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('用另一台设备的浏览器/App 打开此地址',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                  if (_status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_status,
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _card(
              icon: Icons.download_rounded,
              title: '从其他设备接收',
              desc: '对方同样开启「局域网互传」后，把它的地址（或二维码）发给你，你在浏览器打开下载 JSON，再到本页选择文件导入。',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton.icon(
                    onPressed: _startServer,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('查看我的接收地址（即开启共享）'),
                  ),
                  const SizedBox(height: 4),
                  Text('导入用：在浏览器打开对方地址 → 下载 JSON → 这里暂支持对方访问我的地址上传。',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '提示：两台设备需在同一 WiFi 或热点下。数据只在局域网内传输，不经过公网服务器。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String desc,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: _sakuraPink),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Text(desc, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:yhdm/services/storage/storage.dart';

/// 规则动漫图标缓存：首次从网络下载后写入 Hive 永久保存，
/// 之后（含重启）直接从 Hive 读取，不再请求网络。
/// 加载失败返回 null，由调用方显示默认占位图标。
class PluginIconCache {
  PluginIconCache._();
  static final PluginIconCache instance = PluginIconCache._();

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// 内存缓存（避免重复解码），key=URL
  final Map<String, Uint8List> _memory = {};

  /// 加载图标二进制；无缓存时下载并写入 Hive；失败返回 null
  Future<Uint8List?> load(String url) async {
    if (url.isEmpty) return null;
    // 1) 内存
    final mem = _memory[url];
    if (mem != null) return mem;
    // 2) Hive 永久缓存
    final cached = GStorage.pluginIcons.get(url);
    if (cached != null && cached.isNotEmpty) {
      _memory[url] = cached;
      return cached;
    }
    // 3) 网络下载 → 写 Hive + 内存
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(HttpHeaders.acceptHeader, 'image/*');
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) {
        client.close();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await res.forEach(builder.add);
      final bytes = builder.takeBytes();
      client.close();
      if (bytes.isEmpty) return null;
      await GStorage.pluginIcons.put(url, bytes);
      _memory[url] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// 是否已有缓存（含 Hive 与内存）
  bool hasCached(String url) {
    if (url.isEmpty) return false;
    if (_memory.containsKey(url)) return true;
    final c = GStorage.pluginIcons.get(url);
    return c != null && c.isNotEmpty;
  }
}

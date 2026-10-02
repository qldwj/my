import 'package:kazumi/services/logging/logger.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

/// BT / 磁力播放服务
///
/// 负责把 RSS 规则搜到的 magnet 磁力链接，通过 libtorrent 顺序下载 +
/// 本地 HTTP 流式服务器，转成 `http://127.0.0.1:PORT/stream/...` 地址，
/// 再交给 media_kit 播放。这样播放器无需感知 BT，普通直链逻辑完全不变。
class TorrentService {
  TorrentService._();

  static final TorrentService instance = TorrentService._();

  LibtorrentFlutter? _engine;

  /// magnet -> 已生成的 stream url（重复播放同一磁力时直接复用）
  final Map<String, String> _magnetToUrl = {};

  /// magnet -> torrent id
  final Map<String, int> _magnetToId = {};

  bool _initializing = false;

  /// 确保引擎已初始化（幂等）
  Future<void> _ensureInit() async {
    if (_engine != null) return;
    if (_initializing) {
      // 等待正在进行的初始化完成
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (_engine == null && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }
    _initializing = true;
    try {
      await LibtorrentFlutter.init(
        fetchTrackers: true, // 自动注入公共 tracker，提升无 DHT 时的可用性
      );
      _engine = LibtorrentFlutter.instance;
      KazumiLogger().i('TorrentService: libtorrent 引擎初始化完成');
    } finally {
      _initializing = false;
    }
  }

  /// 判断链接是否为磁力链接
  static bool isMagnet(String url) {
    final u = url.toLowerCase();
    return u.startsWith('magnet:') || u.startsWith('magnet?');
  }

  /// 把磁力链接解析成本地 HTTP 流地址，供播放器直接播放
  Future<String> resolveStreamUrl(String magnet) async {
    final cached = _magnetToUrl[magnet];
    if (cached != null && cached.isNotEmpty) return cached;

    await _ensureInit();
    final engine = _engine;
    if (engine == null) {
      throw Exception('BT 引擎初始化失败');
    }

    // 已存在同名磁力 → 复用 torrent id
    final id = _magnetToId[magnet] ?? engine.addMagnet(magnet);
    _magnetToId[magnet] = id;

    // 等待 metadata（拿到文件列表）后再启动流
    await _waitMetadata(id);

    final stream = engine.startStream(id);
    _magnetToUrl[magnet] = stream.url;
    KazumiLogger().i('TorrentService: 磁力已就绪 -> ${stream.url}');
    return stream.url;
  }

  /// 轮询等待磁力 metadata 就绪（默认 60s 超时）
  Future<void> _waitMetadata(int id, {Duration timeout = const Duration(seconds: 60)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final t = engineTorrent(id);
        if (t != null && t.hasMetadata) return;
      } catch (_) {
        // 引擎可能还在初始化某条目，忽略后继续轮询
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw Exception('磁力解析超时（可能无做种者或无 tracker）');
  }

  /// 读取某 torrent 的实时信息（容错封装）
  TorrentInfo? engineTorrent(int id) {
    final engine = _engine;
    if (engine == null) return null;
    try {
      return engine.torrents[id];
    } catch (_) {
      return null;
    }
  }

  /// 释放指定磁力占用的资源（停止流 + 删除文件）
  Future<void> disposeMagnet(String magnet) async {
    final id = _magnetToId[magnet];
    final engine = _engine;
    if (id != null && engine != null) {
      try {
        engine.disposeTorrent(id);
      } catch (e) {
        KazumiLogger().w('TorrentService: 释放磁力失败 $e');
      }
    }
    _magnetToId.remove(magnet);
    _magnetToUrl.remove(magnet);
  }

  /// 清理全部 BT 资源
  Future<void> disposeAll() async {
    final engine = _engine;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (e) {
        KazumiLogger().w('TorrentService: 清理失败 $e');
      }
    }
    _engine = null;
    _magnetToId.clear();
    _magnetToUrl.clear();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/logging/logger.dart';
import 'package:path_provider/path_provider.dart';

/// 弹幕本地库
///
/// 每次成功拉到弹幕就缓存到本地，之后：
///   - 弹幕源挂了 / 网络差 → 直接用本地缓存
///   - 支持导出 `.json` 分享、导入别人的弹幕
///
/// 存储：<App文档目录>/danmaku_cache/<bangumiId>_<episode>.json
class DanmakuCacheService {
  DanmakuCacheService._();

  static Directory? _dir;

  static Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/danmaku_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  static String _fileName(int bangumiId, int episode) =>
      '${bangumiId}_$episode.json';

  /// 保存弹幕（传入原始弹幕列表 JSON）
  static Future<void> save({
    required int bangumiId,
    required int episode,
    required List<dynamic> danmakus,
  }) async {
    if (bangumiId <= 0 || episode <= 0 || danmakus.isEmpty) return;
    try {
      final dir = await _ensureDir();
      final f = File('${dir.path}/${_fileName(bangumiId, episode)}');
      await f.writeAsString(jsonEncode({
        'bangumiId': bangumiId,
        'episode': episode,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'count': danmakus.length,
        'danmakus': danmakus,
      }));
      KazumiLogger().i('DanmakuCache: 已缓存 ${danmakus.length} 条弹幕 '
          '(bgm=$bangumiId ep=$episode)');
    } catch (e) {
      KazumiLogger().w('DanmakuCache: 保存失败', error: e);
    }
  }

  /// 读取缓存；没有则返回 null
  static Future<List<dynamic>?> load({
    required int bangumiId,
    required int episode,
  }) async {
    try {
      final dir = await _ensureDir();
      final f = File('${dir.path}/${_fileName(bangumiId, episode)}');
      if (!await f.exists()) return null;
      final d = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final list = d['danmakus'];
      if (list is List && list.isNotEmpty) {
        KazumiLogger().i('DanmakuCache: 命中本地缓存 ${list.length} 条');
        return list;
      }
      return null;
    } catch (e) {
      KazumiLogger().w('DanmakuCache: 读取失败', error: e);
      return null;
    }
  }

  /// 是否有缓存
  static Future<bool> has({
    required int bangumiId,
    required int episode,
  }) async {
    try {
      final dir = await _ensureDir();
      return await File('${dir.path}/${_fileName(bangumiId, episode)}').exists();
    } catch (_) {
      return false;
    }
  }

  /// 导出到指定路径（分享用）
  static Future<bool> export({
    required int bangumiId,
    required int episode,
    required String targetPath,
  }) async {
    try {
      final dir = await _ensureDir();
      final src = File('${dir.path}/${_fileName(bangumiId, episode)}');
      if (!await src.exists()) return false;
      await src.copy(targetPath);
      return true;
    } catch (e) {
      KazumiLogger().w('DanmakuCache: 导出失败', error: e);
      return false;
    }
  }

  /// 从文件导入
  static Future<int> import({
    required int bangumiId,
    required int episode,
    required String sourcePath,
  }) async {
    try {
      final text = await File(sourcePath).readAsString();
      final d = jsonDecode(text);
      List<dynamic>? list;
      if (d is Map && d['danmakus'] is List) {
        list = d['danmakus'] as List;
      } else if (d is List) {
        list = d;
      }
      if (list == null || list.isEmpty) return 0;
      await save(bangumiId: bangumiId, episode: episode, danmakus: list);
      return list.length;
    } catch (e) {
      KazumiLogger().w('DanmakuCache: 导入失败', error: e);
      return 0;
    }
  }

  /// 缓存占用（字节）
  static Future<int> totalSize() async {
    try {
      final dir = await _ensureDir();
      int total = 0;
      await for (final e in dir.list()) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 清空全部缓存
  static Future<void> clearAll() async {
    try {
      final dir = await _ensureDir();
      await for (final e in dir.list()) {
        if (e is File) await e.delete();
      }
      KazumiLogger().i('DanmakuCache: 已清空');
    } catch (e) {
      KazumiLogger().w('DanmakuCache: 清空失败', error: e);
    }
  }
}

import 'dart:convert';

import 'package:kazumi/services/storage/storage.dart';

/// 自定义收藏分组（本地功能）
///
/// 分组数据以 JSON 字符串存放在 GStorage 设置中，不参与任何云端同步，
/// 不影响 Hive 收藏模型（无需迁移/升级 .g.dart）。
///
/// 存储格式：{"分组名": [subjectId, ...]}
class CollectFolderService {
  CollectFolderService._();

  /// 读取全部分组：分组名 -> 番剧 subjectId 列表（保持顺序）
  static Map<String, List<int>> loadAll() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.collectFolderMap);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, List<int>>{};
      decoded.forEach((key, value) {
        if (key is String && value is List) {
          result[key] = value.whereType<int>().toList();
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, List<int>> data) async {
    await GStorage.putSetting(
      SettingsKeys.collectFolderMap,
      jsonEncode(data),
    );
  }

  /// 新建分组（同名则忽略）
  static Future<bool> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final data = loadAll();
    if (data.containsKey(trimmed)) return false;
    data[trimmed] = <int>[];
    await _save(data);
    return true;
  }

  /// 重命名分组
  static Future<bool> renameFolder(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == oldName) return false;
    final data = loadAll();
    if (!data.containsKey(oldName)) return false;
    if (data.containsKey(trimmed)) return false;
    data[trimmed] = data.remove(oldName)!;
    await _save(data);
    return true;
  }

  /// 删除分组（只删分组关系，不删收藏）
  static Future<void> deleteFolder(String name) async {
    final data = loadAll();
    data.remove(name);
    await _save(data);
  }

  /// 清空分组内的番剧
  static Future<void> clearFolder(String name) async {
    final data = loadAll();
    if (data.containsKey(name)) {
      data[name] = <int>[];
      await _save(data);
    }
  }

  /// 某番剧加入分组（已存在则忽略）
  static Future<bool> addToFolder(String name, int subjectId) async {
    final data = loadAll();
    final list = data.putIfAbsent(name, () => <int>[]);
    if (list.contains(subjectId)) return false;
    list.add(subjectId);
    await _save(data);
    return true;
  }

  /// 某番剧移出分组
  static Future<void> removeFromFolder(String name, int subjectId) async {
    final data = loadAll();
    data[name]?.remove(subjectId);
    await _save(data);
  }

  /// 某番剧当前所在的分组名列表
  static List<String> foldersOf(int subjectId) {
    final data = loadAll();
    return [
      for (final entry in data.entries)
        if (entry.value.contains(subjectId)) entry.key,
    ];
  }

  /// 某番剧是否已在指定分组
  static bool isInFolder(String name, int subjectId) {
    return loadAll()[name]?.contains(subjectId) ?? false;
  }

  /// 指定分组内的 subjectId 集合（用于收藏页过滤）
  static Set<int> idsInFolder(String name) {
    return (loadAll()[name] ?? const <int>[]).toSet();
  }
}

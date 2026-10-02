import 'dart:async';
import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/hive_registrar.g.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/modules/collect/collect_sync_merger.dart';
import 'package:kazumi/modules/search/search_history_module.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/services/storage/history_storage_coordinator.dart';

import 'package:kazumi/services/storage/settings_keys.dart';
export 'package:kazumi/services/storage/settings_keys.dart';

class GStorage {
  /// Don't use favorites box, it's replaced by collectibles.
  static late Box<BangumiItem> favorites;
  static late Box<CollectedBangumi> collectibles;
  static late Box<History> histories;
  static late Box<CollectedBangumiChange> collectChanges;
  static late Box<String> shieldList;
  static late final Box<dynamic> _setting;
  static late Box<SearchHistory> searchHistory;
  static late Box<DownloadRecord> downloads;
  /// 🆕 通知屏蔽列表：键=番剧ID（String），值为番剧名（方便展示）。屏蔽后不再推送该番的更新提醒。
  static late Box<String> notifyMuted;

  // 🆕 收藏/历史快照箱（覆盖型同步前自动备份，可一键回退）
  // 🆕 弹幕缓存箱（key: "<bangumiId>_<episode>"，value 为整包 JSON）
  static late Box<String> danmakuCache;

  // 🆕 需登录规则的 Cookie 持久化箱（key: "plugin_cookie_<规则名>",
  // value 为 {cookies, userAgent, savedAt} Map，重启后仍有效，默认 30 天）
  static late Box<dynamic> pluginCookies;

  static late Box<CollectedBangumi> collectiblesBak;
  static late Box<History> historiesBak;

  /// Hive directory path, initialized during init()
  static String? _hivePath;

  /// Queue to serialize write operations
  static Future<void> _collectChangesWriteQueue = Future.value();

  /// Next ID
  static int _nextCollectChangeId = 0;

  /// Flag to indicate if the next ID has initialized
  static bool _collectChangeIdInitialized = false;

  /// Ensure collect-related write sequentially
  static Future<T> _runCollectChangesWriteExclusive<T>(
    Future<T> Function() action,
  ) {
    final completer = Completer<T>();
    final previousWrite = _collectChangesWriteQueue;

    _collectChangesWriteQueue = (() async {
      try {
        await previousWrite;
      } catch (_) {}

      try {
        completer.complete(await action());
      } catch (e, stackTrace) {
        completer.completeError(e, stackTrace);
      }
    })();

    return completer.future;
  }

  /// init id generator
  static void _initializeNextCollectChangeIdLocked() {
    if (_collectChangeIdInitialized) {
      return;
    }

    var maxExistingId = 0;
    for (final key in collectChanges.keys) {
      if (key is int && key > maxExistingId) {
        maxExistingId = key;
      }
    }

    _nextCollectChangeId = maxExistingId;
    _collectChangeIdInitialized = true;
  }

  /// Generate id for collect change
  static int _generateCollectChangeIdLocked() {
    _initializeNextCollectChangeIdLocked();

    final currentSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Ensure ID is greater than any existing ID, or equal to current timestamp.
    var nextId = _nextCollectChangeId < currentSeconds
        ? currentSeconds
        : _nextCollectChangeId + 1;
    while (collectChanges.containsKey(nextId)) {
      nextId++;
    }
    _nextCollectChangeId = nextId;
    return nextId;
  }

  /// Append a new collect change
  static Future<CollectedBangumiChange> appendCollectChange({
    required int bangumiId,
    required int action,
    required int type,
    int? timestamp,
  }) {
    return _runCollectChangesWriteExclusive(() async {
      final change = CollectedBangumiChange(
        _generateCollectChangeIdLocked(),
        bangumiId,
        action,
        type,
        timestamp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      );
      await collectChanges.put(change.id, change);
      await collectChanges.flush();
      return change;
    });
  }

  /// Update an existing collect change
  static Future<void> putCollectChange(CollectedBangumiChange change) {
    return _runCollectChangesWriteExclusive(() async {
      _initializeNextCollectChangeIdLocked();
      if (change.id > _nextCollectChangeId) {
        _nextCollectChangeId = change.id;
      }
      await collectChanges.put(change.id, change);
      await collectChanges.flush();
    });
  }

  /// Put a collectible using the same write queue
  static Future<void> putCollectible(CollectedBangumi collectible) {
    return _runCollectChangesWriteExclusive(() async {
      final id = collectible.bangumiItem.id;
      await collectibles.put(id, collectible);
      await collectibles.flush();
      // ⭐ 写后校验（"追了下次没了"的根因排查）：
      //   1) Hive 的 put 只是排到 write queue；flush 排空 write queue 并把
      //      bytes 交给 RandomAccessFile，**不一定 fsync**。某些机型 / 进程
      //      被 force-stop 时，会出现"UI 看着有、重启就丢"的现象。
      //   2) 这里立即 get 回来比对：若内存 box 里都没有，说明 put 被吞了；
      //      若 box 有但 id/type/name 不一致，说明 adapter 编解码异常。
      //   3) 不一致时再 put + flush 一次兜底，并把警告打到日志，方便复现。
      CollectedBangumi? verify;
      try {
        verify = collectibles.get(id);
      } catch (e) {
        KazumiLogger().e(
          'GStorage: collectible 写后读回异常 id=$id',
          error: e,
        );
      }
      final bool ok = verify != null &&
          verify.type == collectible.type &&
          verify.bangumiItem.id == collectible.bangumiItem.id;
      if (!ok) {
        KazumiLogger().w(
          'GStorage: collectible 写后校验失败 id=$id，重试一次'
          '（type 期望=${collectible.type} 实际=${verify?.type}）',
        );
        await collectibles.put(id, collectible);
        await collectibles.flush();
        try {
          final again = collectibles.get(id);
          if (again == null) {
            KazumiLogger().e(
              'GStorage: collectible 二次写入后仍读不到 id=$id，'
              '本机 Hive 可能未正确持久化（检查 /data/data/<pkg>/files/hive/collectibles.hive）',
            );
          }
        } catch (_) {}
      }
    });
  }

  /// Delete a collectible using the shared collect write queue.
  static Future<void> deleteCollectible(int bangumiId) {
    return _runCollectChangesWriteExclusive(() async {
      await collectibles.delete(bangumiId);
      await collectibles.flush();
    });
  }

  static Future init() async {
    _hivePath = '${(await getApplicationSupportDirectory()).path}/hive';

    Hive.registerAdapters();

    // Open each box with automatic recovery on corruption
    favorites = await _openBoxSafe<BangumiItem>('favorites');
    collectibles = await _openBoxSafe<CollectedBangumi>('collectibles');
    histories = await _openBoxSafe<History>('histories');
    _setting = await _openBoxSafe<dynamic>('setting');
    collectChanges =
        await _openBoxSafe<CollectedBangumiChange>('collectchanges');
    shieldList = await _openBoxSafe<String>('shieldList');
    searchHistory = await _openBoxSafe<SearchHistory>('searchHistory');
    downloads = await _openBoxSafe<DownloadRecord>('downloads');
    notifyMuted = await _openBoxSafe<String>('notifyMuted');
    danmakuCache = await _openBoxSafe<String>('danmakuCache');
    pluginCookies = await _openBoxSafe<dynamic>('pluginCookies');
    collectiblesBak =
        await _openBoxSafe<CollectedBangumi>('collectiblesBak');
    historiesBak = await _openBoxSafe<History>('historiesBak');

    // ⭐ 启动诊断：收藏盘里到底有没有数据，一眼看出是"没写进去"还是"被覆盖"。
    //   如果用户报"追番没了"，先看这条日志里 length 是不是和 UI 看到的一致。
    try {
      KazumiLogger().i(
        'GStorage: booted. collectibles=${collectibles.length}, '
        'bak=${collectiblesBak.length}, changes=${collectChanges.length}, '
        'histories=${histories.length}, path=$_hivePath',
      );
    } catch (e) {
      KazumiLogger().w('GStorage: 启动诊断读取异常', error: e);
    }
  }

  /// 🆕 覆盖型同步（云端→本机）前调用：把当前收藏/历史整体快照一份
  static Future<void> snapshotBeforeOverwrite() async {
    try {
      await collectiblesBak.clear();
      await collectiblesBak.putAll(collectibles.toMap());
      await collectiblesBak.flush();
      await historiesBak.clear();
      await historiesBak.putAll(histories.toMap());
      await historiesBak.flush();
      KazumiLogger().i(
        'GStorage: snapshot ok (collect=${collectibles.length}, history=${histories.length})',
      );
    } catch (e) {
      KazumiLogger().e('GStorage: snapshot failed', error: e);
    }
  }

  /// 🆕 是否已有可用快照
  static bool get hasSnapshot => collectiblesBak.isNotEmpty;

  static int get snapshotCollectCount => collectiblesBak.length;

  /// 🆕 用快照回退收藏（只回退收藏，历史体积大不默认回退）
  static Future<int> restoreCollectiblesFromSnapshot() async {
    if (!hasSnapshot) return 0;
    final bak = collectiblesBak.toMap();
    await collectibles.clear();
    await collectibles.putAll(bak);
    await collectibles.flush();
    return collectibles.length;
  }

  /// Open a Hive box with automatic recovery on corruption.
  /// If the box is corrupted, salvage readable records, then delete and recreate.
  static Future<Box<T>> _openBoxSafe<T>(String boxName) async {
    try {
      return await Hive.openBox<T>(boxName);
    } catch (e) {
      KazumiLogger().e(
          'GStorage: Box "$boxName" corrupted, attempting recovery',
          error: e);

      // 🆕 先抢救能读出的记录：一条坏记录不再让整箱数据陪葬
      final salvaged = await _salvageBox<T>(boxName);

      // 先把“坏箱”原样另存一份再重建：salvage 失败时还有人工抢救机会
      try {
        final src = File('$_hivePath/$boxName.hive');
        if (await src.exists()) {
          await src.copy('$_hivePath/$boxName.hive.corrupted-${DateTime.now().millisecondsSinceEpoch}');
        }
      } catch (_) {}

      // Delete the corrupted box files
      await _deleteBoxFiles(boxName);

      // Try to open again (will create a new empty box)
      try {
        final box = await Hive.openBox<T>(boxName);
        if (salvaged != null && salvaged.isNotEmpty) {
          await box.putAll(salvaged);
          KazumiLogger().i(
              'GStorage: Box "$boxName" recovered, salvaged ${salvaged.length} record(s)');
        } else {
          KazumiLogger()
              .i('GStorage: Box "$boxName" recovered successfully (data lost)');
        }
        return box;
      } catch (e2) {
        KazumiLogger()
            .e('GStorage: Failed to recover box "$boxName"', error: e2);
        rethrow;
      }
    }
  }

  /// 🆕 抢救损坏箱子中仍能读出的记录（按 key 逐条 try，坏记录跳过）
  static Future<Map<dynamic, T>?> _salvageBox<T>(String boxName) async {
    if (_hivePath == null) return null;
    final boxFile = File('$_hivePath/$boxName.hive');
    if (!await boxFile.exists()) return null;
    try {
      final bytes = await boxFile.readAsBytes();
      final temp = await Hive.openBox<T>('${boxName}_salvage_tmp',
          bytes: bytes);
      final result = <dynamic, T>{};
      var skipped = 0;
      for (final key in temp.keys) {
        try {
          final value = temp.get(key);
          if (value != null) result[key] = value;
        } catch (_) {
          skipped++;
        }
      }
      await temp.close();
      if (skipped > 0) {
        KazumiLogger().w(
            'GStorage: salvaged box "$boxName", skipped $skipped corrupt record(s)');
      }
      return result;
    } catch (e) {
      KazumiLogger().w('GStorage: salvage failed for "$boxName"', error: e);
      return null;
    }
  }

  /// Delete Hive box files for a given box name
  static Future<void> _deleteBoxFiles(String boxName) async {
    if (_hivePath == null) return;

    final boxFile = File('$_hivePath/$boxName.hive');
    final lockFile = File('$_hivePath/$boxName.lock');

    try {
      if (await boxFile.exists()) {
        await boxFile.delete();
        KazumiLogger().i('GStorage: Deleted corrupted box file: $boxName.hive');
      }
      if (await lockFile.exists()) {
        await lockFile.delete();
        KazumiLogger().i('GStorage: Deleted lock file: $boxName.lock');
      }
    } catch (e) {
      KazumiLogger()
          .e('GStorage: Failed to delete box files for "$boxName"', error: e);
    }
  }

  static Future<void> backupBox(String boxName, String backupFilePath) async {
    final appDocumentDir = await getApplicationSupportDirectory();
    final hiveBoxFile = File('${appDocumentDir.path}/hive/$boxName.hive');
    if (await hiveBoxFile.exists()) {
      await hiveBoxFile.copy(backupFilePath);
      KazumiLogger().i('GStorage: backup success: $backupFilePath');
    } else {
      KazumiLogger().w('GStorage: Hive box does not exist: $boxName');
    }
  }

  static Future<void> patchHistory(String backupFilePath) async {
    final backupFile = File(backupFilePath);
    final backupContent = await backupFile.readAsBytes();
    final tempBox = await Hive.openBox('tempHistoryBox', bytes: backupContent);
    try {
      final tempBoxItems = tempBox.toMap().entries;
      await HistoryStorageCoordinator().run(() async {
        for (final tempBoxItem in tempBoxItems) {
          final tempHistory = tempBoxItem.value as History;
          tempHistory.entryKind =
              HistoryEntryKind.normalize(tempHistory.entryKind);
          final targetKey = tempHistory.key;
          final existing = histories.get(targetKey);
          if (existing == null ||
              existing.lastWatchTime.isBefore(tempHistory.lastWatchTime)) {
            await histories.put(targetKey, tempHistory);
          }
        }
      });
    } finally {
      await tempBox.close();
    }
  }

  static Future<void> restoreCollectibles(String backupFilePath) async {
    final backupFile = File(backupFilePath);
    final backupContent = await backupFile.readAsBytes();
    final tempBox =
        await Hive.openBox('tempCollectiblesBox', bytes: backupContent);
    final tempBoxItems = tempBox.toMap().entries;
    KazumiLogger().i(
        'WebDav: restoring collectibles. tempCollectiblesBox length ${tempBoxItems.length}');

    // 🛡️ 远端备份盒为空 → 绝不清空本机
    if (tempBoxItems.isEmpty) {
      KazumiLogger().w(
          'WebDav: 远端备份为空，跳过覆盖（本机 ${collectibles.length} 条保留）');
      await tempBox.close();
      return;
    }
    await snapshotBeforeOverwrite();
    await collectibles.clear();
    await collectibles.flush();
    for (var tempBoxItem in tempBoxItems) {
      await collectibles.put(tempBoxItem.key, tempBoxItem.value);
    }
    await collectibles.flush();
    await tempBox.close();
  }

  static Future<List<CollectedBangumi>> getCollectiblesFromFile(
      String backupFilePath) async {
    final backupFile = File(backupFilePath);
    final backupContent = await backupFile.readAsBytes();
    final tempBox =
        await Hive.openBox('tempCollectiblesBox', bytes: backupContent);
    final tempBoxItems = tempBox.toMap().entries;
    KazumiLogger().i(
        'WebDav: get collectibles from file. tempCollectiblesBox length ${tempBoxItems.length}');

    final List<CollectedBangumi> collectibles = [];
    for (var tempBoxItem in tempBoxItems) {
      collectibles.add(tempBoxItem.value);
    }
    await tempBox.close();
    return collectibles;
  }

  static Future<List<CollectedBangumiChange>> getCollectChangesFromFile(
      String backupFilePath) async {
    final backupFile = File(backupFilePath);
    final backupContent = await backupFile.readAsBytes();
    final tempBox =
        await Hive.openBox('tempCollectChangesBox', bytes: backupContent);
    final tempBoxItems = tempBox.toMap().entries;
    KazumiLogger().i(
        'WebDav: get collectChanges from file. tempCollectChangesBox length ${tempBoxItems.length}');

    final List<CollectedBangumiChange> collectChanges = [];
    for (var tempBoxItem in tempBoxItems) {
      collectChanges.add(tempBoxItem.value);
    }
    await tempBox.close();
    return collectChanges;
  }

  static Future<void> patchCollectibles(
      List<CollectedBangumi> remoteCollectibles,
      List<CollectedBangumiChange> remoteChanges) async {
    await _runCollectChangesWriteExclusive(() async {
      final mergeResult = CollectSyncMerger.mergeWebDav(
        localCollectibles: collectibles.values.toList(),
        localChanges: collectChanges.values.toList(),
        remoteCollectibles: remoteCollectibles,
        remoteChanges: remoteChanges,
      );

      // Update local storage
      // 🛡️ 兜底防御：合并后为空但本机当前非空 → 拒绝覆盖。
      //   正常双向合并不会出现这种情况（取并集），但任何上游数据异常
      //   （云端被另一设备推空 / 解析失败 / adapter 抛错被吞）都不应该
      //   把本机追番清空。用户反馈的"重启后收藏全没"就是这条路径。
      final int localBefore = collectibles.length;
      if (mergeResult.collectibles.isEmpty && localBefore > 0) {
        KazumiLogger().w(
          'WebDav: 合并结果为空但本机有 $localBefore 条收藏，拒绝覆盖；'
          '请检查云端 collectibles.tmp / collectchanges.tmp 是否被异常推空',
        );
        return;
      }
      // 🛡️ 覆盖前留一份快照，误同步可在「同步设置」里一键回退
      await snapshotBeforeOverwrite();
      await collectibles.clear();
      await collectibles.flush();
      for (var collect in mergeResult.collectibles) {
        // ⚠️ 防御：WebDAV 远端盒子里的 type 可能是 0 或 >5（其他端/旧版本写入），
        // 直接入库会导致追番页 `type-1` 数组越界白屏，这里钳制到 1..5。
        final t = collect.type;
        if (t < 1 || t > 5) {
          collect = CollectedBangumi(collect.bangumiItem, collect.time, 1);
        }
        await collectibles.put(collect.bangumiItem.id, collect);
      }
      await collectibles.flush();

      await collectChanges.clear();
      for (var change in mergeResult.changes) {
        await collectChanges.put(change.id, change);
      }
      await collectChanges.flush();

      _collectChangeIdInitialized = false;
      _initializeNextCollectChangeIdLocked();
    });
  }

  static T getSetting<T>(
    SettingKey<T> key, {
    SettingContext context = const SettingContext(),
  }) {
    final defaultValue = key.resolveDefault(context);
    final storedValue = _setting.get(key.name);
    if (storedValue is T) {
      return storedValue;
    }
    return defaultValue;
  }

  static Future<void> putSetting<T>(SettingKey<T> key, T value) async {
    await _setting.put(key.name, value);
  }

  static List<String> getStringListSettingByName(
    String key, {
    List<String> defaultValue = const [],
  }) {
    final storedValue = _setting.get(key);
    if (storedValue is List) {
      return storedValue.whereType<String>().toList();
    }
    return defaultValue;
  }

  static Future<void> putStringListSettingByName(
    String key,
    List<String> value,
  ) async {
    await _setting.put(key, value);
  }

  static Future<void> resetSettings(Iterable<SettingKey<Object?>> keys) async {
    await _setting.deleteAll(keys.map((key) => key.name));
    await _setting.flush();
  }

  static Future<void> resetPlayerSettings() async {
    await resetSettings(SettingsKeys.byGroup(SettingGroup.player));
  }

  static Future<void> resetDanmakuSettings() async {
    await resetSettings(SettingsKeys.byGroup(SettingGroup.danmaku));
  }

  static Stream<void> watchSettings(Iterable<SettingKey<Object?>> keys) {
    final names = keys.map((key) => key.name).toSet();
    return _setting.watch().where((event) => names.contains(event.key)).map((_) {});
  }

  GStorage._();
}

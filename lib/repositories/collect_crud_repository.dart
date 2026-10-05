import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/modules/bangumi/bangumi_item.dart';
import 'package:yhdm/modules/collect/collect_module.dart';
import 'package:yhdm/modules/collect/collect_change_module.dart';
import 'package:yhdm/services/logging/logger.dart';

/// 收藏CRUD数据访问接口
///
/// 提供收藏数据的增删改查操作
abstract class ICollectCrudRepository {
  /// 获取所有收藏
  List<CollectedBangumi> getAllCollectibles();

  /// 获取单个收藏
  ///
  /// [id] 番剧ID
  /// 返回收藏对象，如果不存在返回null
  CollectedBangumi? getCollectible(int id);

  /// 获取收藏类型
  ///
  /// [id] 番剧ID
  /// 返回收藏类型值，未收藏返回0
  int getCollectType(int id);

  /// 添加或更新收藏
  ///
  /// [bangumiItem] 番剧信息
  /// [type] 收藏类型
  Future<void> addCollectible(BangumiItem bangumiItem, int type);

  /// 更新收藏的番剧信息
  ///
  /// [bangumiItem] 更新后的番剧信息
  Future<void> updateCollectible(BangumiItem bangumiItem);

  /// 删除收藏
  ///
  /// [id] 番剧ID
  Future<void> deleteCollectible(int id);

  /// 记录收藏变更（用于WebDAV同步）
  ///
  /// [change] 变更记录
  Future<void> addCollectChange(CollectedBangumiChange change);

  /// 获取旧版收藏列表（用于迁移）
  List<BangumiItem> getFavorites();

  /// 清空旧版收藏（迁移后）
  Future<void> clearFavorites();
}

/// 收藏CRUD数据访问实现类
///
/// 基于Hive实现的收藏CRUD数据访问层
class CollectCrudRepository implements ICollectCrudRepository {
  final _collectiblesBox = GStorage.collectibles;
  final _favoritesBox = GStorage.favorites;

  @override
  List<CollectedBangumi> getAllCollectibles() {
    // ⚠️ 不要用 box.values.cast<T>().toList()：只要箱里有**一条**类型不符/损坏的
    // 记录，整批读取就会抛异常并被 catch 成 []，用户看到的就是
    // “追番页全空”（其实数据还在盘上）。这里改成逐 key 读、坏记录跳过。
    final result = <CollectedBangumi>[];
    var broken = 0;
    for (final key in _collectiblesBox.keys.toList()) {
      try {
        final value = _collectiblesBox.get(key);
        if (value is CollectedBangumi) {
          result.add(value);
        } else {
          broken++;
          KazumiLogger().w(
            'GStorage: collectible key=$key 类型异常(${value.runtimeType})，已跳过',
          );
        }
      } catch (e) {
        broken++;
        KazumiLogger().w(
          'GStorage: collectible key=$key 读取失败，已跳过: $e',
        );
      }
    }
    if (broken > 0) {
      KazumiLogger().w(
        'GStorage: 收藏共 ${result.length} 条正常、$broken 条异常已跳过',
      );
    }
    return result;
  }

  @override
  CollectedBangumi? getCollectible(int id) {
    try {
      return _collectiblesBox.get(id);
    } catch (e) {
      KazumiLogger().w(
        'GStorage: get collectible failed. id=$id',
        error: e,
      );
      return null;
    }
  }

  @override
  int getCollectType(int id) {
    try {
      final collectible = _collectiblesBox.get(id);
      return collectible?.type ?? 0;
    } catch (e) {
      KazumiLogger().w(
        'GStorage: get collect type failed. id=$id',
        error: e,
      );
      return 0;
    }
  }

  @override
  Future<void> addCollectible(BangumiItem bangumiItem, int type) async {
    try {
      final collectedBangumi = CollectedBangumi(
        bangumiItem,
        DateTime.now(),
        type,
      );
      await GStorage.putCollectible(collectedBangumi);
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: add collectible failed. id=${bangumiItem.id}, type=$type',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> updateCollectible(BangumiItem bangumiItem) async {
    try {
      final collectible = _collectiblesBox.get(bangumiItem.id);
      if (collectible == null) {
        KazumiLogger().i(
          'GStorage: update collectible failed. collectible not found, id=${bangumiItem.id}',
        );
        return;
      }
      collectible.bangumiItem = bangumiItem;
      await GStorage.putCollectible(collectible);
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: update collectible failed. id=${bangumiItem.id}',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> deleteCollectible(int id) async {
    try {
      await GStorage.deleteCollectible(id);
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: delete collectible failed. id=$id',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> addCollectChange(CollectedBangumiChange change) async {
    try {
      await GStorage.putCollectChange(change);
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: record collect change failed. changeId=${change.id}',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  List<BangumiItem> getFavorites() {
    try {
      // 同样逐条容错，避免一条坏记录让整批“旧版收藏”读不出来
      final list = <BangumiItem>[];
      for (final key in _favoritesBox.keys.toList()) {
        try {
          final v = _favoritesBox.get(key);
          if (v is BangumiItem) list.add(v);
        } catch (_) {}
      }
      return list;
    } catch (e) {
      KazumiLogger().i(
        'GStorage: get favorites failed',
        error: e,
      );
      return [];
    }
  }

  @override
  Future<void> clearFavorites() async {
    try {
      await _favoritesBox.clear();
      await _favoritesBox.flush();
    } catch (e) {
      KazumiLogger().i(
        'GStorage: clear favorites failed',
        error: e,
      );
      rethrow;
    }
  }
}

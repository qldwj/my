import 'package:kazumi/modules/bangumi/bangumi_collection.dart';
import 'package:kazumi/modules/bangumi/sync_priority.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type_mapper.dart';

class CollectiblesMergeResult {
  const CollectiblesMergeResult({
    required this.collectibles,
    required this.changes,
  });

  final List<CollectedBangumi> collectibles;
  final List<CollectedBangumiChange> changes;
}

class BangumiUploadMutation {
  const BangumiUploadMutation({
    required this.bangumiId,
    required this.type,
  });

  final int bangumiId;
  final int type;
}

class BangumiLocalMutation {
  const BangumiLocalMutation({
    required this.collectible,
    required this.changeAction,
  });

  final CollectedBangumi collectible;
  final int changeAction;
}

class BangumiCollectiblesMergePlan {
  const BangumiCollectiblesMergePlan({
    required this.localOnlyUploads,
    required this.remoteOnlyPuts,
    required this.conflictUploads,
    required this.conflictLocalUpdates,
  });

  final List<BangumiUploadMutation> localOnlyUploads;
  final List<BangumiLocalMutation> remoteOnlyPuts;
  final List<BangumiUploadMutation> conflictUploads;
  final List<BangumiLocalMutation> conflictLocalUpdates;

  int get totalOperations =>
      localOnlyUploads.length +
      remoteOnlyPuts.length +
      conflictUploads.length +
      conflictLocalUpdates.length;
}

class CollectSyncMerger {
  static CollectiblesMergeResult mergeWebDav({
    required List<CollectedBangumi> localCollectibles,
    required List<CollectedBangumiChange> localChanges,
    required List<CollectedBangumi> remoteCollectibles,
    required List<CollectedBangumiChange> remoteChanges,
  }) {
    // ⭐ 合并语义（v2）：取「云端 ∪ 本机」并集，删除以「显式 delete change」为准。
    //   旧实现是「以云端为基底」，本机里只要有条目在云端不存在、又恰好
    //   没有未推送的 add change（旧版本同步遗留 / 上次同步后已 push 但
    //   云端被另一台设备覆盖回空），重启同步就会被悄悄清掉——
    //   用户反馈的「上次追番了，下次启动就没了」就是这条。
    final byId = <int, CollectedBangumi>{};
    // 1. 先放本机（保留本机条目作为基线）
    for (final item in localCollectibles) {
      byId[item.bangumiItem.id] = _copyCollectible(item);
    }
    // 2. 云端覆盖（远端更新优先：同 id 取云端版本，云端独有的也补进来）
    for (final item in remoteCollectibles) {
      byId[item.bangumiItem.id] = _copyCollectible(item);
    }

    // 3. 把本机新增（未在云端出现的 change）按 action 应用，沿用旧逻辑
    final newLocalChanges = localChanges.where((localChange) {
      return !remoteChanges
          .any((remoteChange) => remoteChange.id == localChange.id);
    }).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final change in newLocalChanges) {
      if (change.action == 3) {
        // 显式删除：本机里这条要删掉，云端有的也覆盖删
        byId.remove(change.bangumiID);
        continue;
      }

      final localCollectible = _findCollectible(
        localCollectibles,
        change.bangumiID,
      );
      if (localCollectible == null) {
        continue;
      }

      final changedCollectible = CollectedBangumi(
        localCollectible.bangumiItem,
        localCollectible.time,
        change.type,
      );
      // action==1 新增 / action==2 状态变更：都以本机最新状态写回
      byId[change.bangumiID] = changedCollectible;
    }

    final mergedCollectibles = byId.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    final mergedChanges = <int, CollectedBangumiChange>{
      for (final change in remoteChanges) change.id: change,
      for (final change in newLocalChanges) change.id: change,
    }.values.toList();

    return CollectiblesMergeResult(
      collectibles: mergedCollectibles,
      changes: mergedChanges,
    );
  }

  static BangumiCollectiblesMergePlan planBangumi({
    required List<CollectedBangumi> localCollectibles,
    required List<BangumiCollection> remoteCollections,
    required BangumiSyncPriority priority,
  }) {
    final localMap = {
      for (final item in localCollectibles) item.bangumiItem.id: item,
    };
    final remoteMap = <int, BangumiCollection>{};
    for (final item in remoteCollections) {
      final remoteCollectType = item.type.toCollectType();
      if (!remoteCollectType.isCollected) {
        continue;
      }
      remoteMap[item.bangumiId] = item;
    }

    final localOnlyIds = localMap.keys
        .toSet()
        .difference(remoteMap.keys.toSet())
        .toList()
      ..sort();
    final remoteOnlyIds = remoteMap.keys
        .toSet()
        .difference(localMap.keys.toSet())
        .toList()
      ..sort();
    final sharedIds = localMap.keys
        .toSet()
        .intersection(remoteMap.keys.toSet())
        .toList()
      ..sort();
    final mismatchIds = <int>[];
    for (final id in sharedIds) {
      if (localMap[id]!.type != remoteMap[id]!.type.toCollectType().value) {
        mismatchIds.add(id);
      }
    }

    final localOnlyUploads = [
      for (final id in localOnlyIds)
        BangumiUploadMutation(bangumiId: id, type: localMap[id]!.type),
    ];
    final remoteOnlyPuts = [
      for (final id in remoteOnlyIds)
        BangumiLocalMutation(
          collectible: _fromBangumiCollection(remoteMap[id]!),
          changeAction: 1,
        ),
    ];

    final conflictUploads = <BangumiUploadMutation>[];
    final conflictLocalUpdates = <BangumiLocalMutation>[];
    if (priority == BangumiSyncPriority.localFirst) {
      for (final id in mismatchIds) {
        conflictUploads.add(
          BangumiUploadMutation(bangumiId: id, type: localMap[id]!.type),
        );
      }
    } else {
      for (final id in mismatchIds) {
        conflictLocalUpdates.add(
          BangumiLocalMutation(
            collectible: _fromBangumiCollection(remoteMap[id]!),
            changeAction: 2,
          ),
        );
      }
    }

    return BangumiCollectiblesMergePlan(
      localOnlyUploads: localOnlyUploads,
      remoteOnlyPuts: remoteOnlyPuts,
      conflictUploads: conflictUploads,
      conflictLocalUpdates: conflictLocalUpdates,
    );
  }

  static CollectedBangumi _fromBangumiCollection(BangumiCollection remote) {
    final localType = remote.type.toCollectType();
    return CollectedBangumi(
      remote.toBangumiItem(),
      remote.updatedAt,
      localType.value,
    );
  }

  static CollectedBangumi? _findCollectible(
    List<CollectedBangumi> collectibles,
    int bangumiId,
  ) {
    for (final collectible in collectibles) {
      if (collectible.bangumiItem.id == bangumiId) {
        return collectible;
      }
    }
    return null;
  }

  static CollectedBangumi _copyCollectible(CollectedBangumi collectible) {
    return CollectedBangumi(
      collectible.bangumiItem,
      collectible.time,
      collectible.type,
    );
  }

  CollectSyncMerger._();
}

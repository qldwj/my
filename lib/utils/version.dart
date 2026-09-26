import 'dart:math';

/// 判断是否需要更新（标准 semver 风格的预发布语义）
///
/// 版本顺序（从小到大）：
///   2.3.8  <  2.3.9-beta  <  2.3.9-beta2  <  2.3.9
///
/// 即：**预发布版（带 -后缀）永远小于同版本的正式版**，预发布之间按后缀排序。
///
/// 由此得到的更新行为：
/// | 本机          | 远程          | 结果                       |
/// |---------------|---------------|----------------------------|
/// | 2.3.8         | 2.3.9-beta    | ✅ 更新（数字更大）          |
/// | 2.3.9-beta    | 2.3.9-beta    | ⛔ 相同，不提示             |
/// | 2.3.9-beta    | 2.3.9-beta2   | ✅ 更新（后缀更大）          |
/// | 2.3.9-beta    | 2.3.9         | ✅ 更新（预发布 → 正式版）   |
/// | 2.3.9         | 2.3.9-beta    | ⛔ 不提示（禁止降级！）      |
/// | 2.3.8         | 2.3.9         | ✅ 更新                     |
///
/// ⚠️ 关键前提：**测试版构建的内部版本号必须带 -后缀**（如 2.3.9-beta）。
///    如果测试版把版本号写成纯数字 2.3.9，会和正式版 2.3.9 撞号，
///    导致「测试版检测不到正式版、正式版也检测不到测试版」的双向死锁。
bool needUpdate(String localVersion, String remoteVersion) {
  // 分离核心版本和后缀
  String cleanVersion(String v) => v.split('-').first;
  String? getSuffix(String v) {
    final parts = v.split('-');
    return parts.length > 1 ? parts.skip(1).join('-') : null;
  }

  try {
    final localClean = cleanVersion(localVersion);
    final remoteClean = cleanVersion(remoteVersion);

    final localParts =
        localClean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final remoteParts =
        remoteClean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final maxLength = max(localParts.length, remoteParts.length);

    // 1) 先比数字部分
    for (int i = 0; i < maxLength; i++) {
      final local = i < localParts.length ? localParts[i] : 0;
      final remote = i < remoteParts.length ? remoteParts[i] : 0;
      if (remote > local) return true;
      if (remote < local) return false;
    }

    // 2) 数字完全相同，比较后缀（预发布）
    final localSuffix = getSuffix(localVersion);
    final remoteSuffix = getSuffix(remoteVersion);

    // 本机是预发布、远程是正式版 → 升级到正式版
    if (localSuffix != null && remoteSuffix == null) return true;

    // 本机是正式版、远程是预发布 → ⛔ 不提示（避免正式版被"降级"到同版本测试版）
    if (localSuffix == null && remoteSuffix != null) return false;

    // 都是预发布 → 按后缀排序（beta < beta2 < rc1 ...）
    if (localSuffix != null && remoteSuffix != null) {
      return remoteSuffix.compareTo(localSuffix) > 0;
    }

    // 都是正式版且数字相同 → 没有更新
    return false;
  } catch (e) {
    // 任何解析异常都视为有新版本（保守策略）
    return true;
  }
}

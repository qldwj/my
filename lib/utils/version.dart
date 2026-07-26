import 'dart:math';

bool needUpdate(String localVersion, String remoteVersion) {
  // 分离核心版本和后缀
  String cleanVersion(String v) {
    return v.split('-').first;
  }

  String? getSuffix(String v) {
    final parts = v.split('-');
    return parts.length > 1 ? parts.skip(1).join('-') : null;
  }

  try {
    final localClean = cleanVersion(localVersion);
    final remoteClean = cleanVersion(remoteVersion);

    final localParts = localClean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final remoteParts = remoteClean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final maxLength = max(localParts.length, remoteParts.length);

    for (int i = 0; i < maxLength; i++) {
      final local = i < localParts.length ? localParts[i] : 0;
      final remote = i < remoteParts.length ? remoteParts[i] : 0;
      if (remote > local) return true;
      if (remote < local) return false;
    }

    // 数字部分完全相同：比较后缀
    final localSuffix = getSuffix(localVersion);
    final remoteSuffix = getSuffix(remoteVersion);

    // 无后缀 > 有后缀（正式版优先于测试版）
    if (localSuffix != null && remoteSuffix == null) {
      return true; // 本地有后缀，远程无后缀 → 远程是正式版，需要更新
    }
    if (localSuffix == null && remoteSuffix != null) {
      return false; // 本地正式版，远程测试版 → 不需要更新
    }

    // 两者都有后缀：按字母顺序比较，如果远程后缀更大则更新
    if (localSuffix != null && remoteSuffix != null) {
      return remoteSuffix.compareTo(localSuffix) > 0;
    }

    // 都无后缀，版本完全相同
    return false;
  } catch (e) {
    // 任何解析异常都视为有新版本（保守策略）
    return true;
  }
}
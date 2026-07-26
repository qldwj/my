import 'dart:math';

bool needUpdate(String localVersion, String remoteVersion) {
  // 清理版本号：移除 - 后面的所有内容（如 -bate, -beta, -alpha）
  // 这样 2.2.6-bate 变成 2.2.6，用于比较数字部分
  String cleanVersion(String v) {
    // 如果有 -，取 - 前面的部分；没有则返回原字符串
    if (v.contains('-')) {
      return v.split('-').first;
    }
    return v;
  }

  try {
    final localClean = cleanVersion(localVersion);
    final remoteClean = cleanVersion(remoteVersion);

    final localVersionList = localClean.split('.');
    final remoteVersionList = remoteClean.split('.');
    final maxLength = max(localVersionList.length, remoteVersionList.length);

    for (var i = 0; i < maxLength; i++) {
      // 安全解析，如果无法转为数字则视为 0
      int parseSegment(String? segment) {
        if (segment == null || segment.isEmpty) return 0;
        try {
          return int.parse(segment);
        } catch (_) {
          return 0; // 非数字段视为 0
        }
      }

      final localSegment = i < localVersionList.length
          ? parseSegment(localVersionList[i])
          : 0;
      final remoteSegment = i < remoteVersionList.length
          ? parseSegment(remoteVersionList[i])
          : 0;

      if (remoteSegment > localSegment) {
        return true;
      } else if (remoteSegment < localSegment) {
        return false;
      }
    }
    return false;
  } catch (e) {
    // 任何解析异常都视为有新版本（保守策略）
    return true;
  }
}
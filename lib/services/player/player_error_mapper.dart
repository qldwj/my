/// 播放器错误分类与提示文案
///
/// 目的：区分「网络抖动 / 源端波动」和「真正的内部错误」。
/// 网络类问题播放器通常会自动重连、继续缓冲，用户往往还能正常观看，
/// 这时弹一大串 `播放器内部错误 ...` 只会让人难受，所以直接静默；
/// 只有真正无法自行恢复的内部错误才提示。
class PlayerErrorMapper {
  const PlayerErrorMapper._();

  /// 网络/源端波动类错误特征（小写匹配）
  static const List<String> _networkSignatures = <String>[
    'connection refused',
    'connection reset',
    'connection aborted',
    'connection closed',
    'connection attempt failed',
    'could not connect',
    'failed to connect',
    'network is unreachable',
    'network unreachable',
    'no route to host',
    'could not resolve host',
    'temporary failure in name resolution',
    'name or service not known',
    'timed out',
    'timeout',
    'i/o error',
    'input/output error',
    'broken pipe',
    'unexpected eof',
    'end of file',
    'eof reached',
    'http error',
    'server returned',
    'service unavailable',
    'bad gateway',
    'gateway timeout',
    'forbidden',
    'not found',
    'tls',
    'ssl',
    'handshake',
    'socket',
    'proxy',
    'read error',
    'write error',
    'stream error',
    'failed to open',
    'failed to seek',
    'failed to read',
    'not responding',
    'unable to open',
  ];

  /// 是否为「网络 / 源端波动」类错误。
  ///
  /// 这类错误可以静默处理：不打断用户，也不弹长串异常文本。
  static bool isNetworkIssue(Object error) {
    final message = error.toString().toLowerCase();
    for (final signature in _networkSignatures) {
      if (message.contains(signature)) return true;
    }
    return false;
  }

  /// 网络类错误的简短提示（只在必须告知用户时使用）
  static const String networkHint = '网络不稳定，正在重试…';

  /// 真正的内部错误：给出简短提示，不再拼接长串异常与视频地址
  static String internalErrorMessage(Object error) {
    var detail = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (detail.length > 60) {
      detail = '${detail.substring(0, 60)}…';
    }
    return detail.isEmpty ? '播放器内部错误' : '播放器内部错误：$detail';
  }

  static String? toActionableMessage(
    Object error, {
    required bool isBuffering,
  }) {
    final message = error.toString();
    if (message.contains('Failed to recognize file format') ||
        (isBuffering && message.contains('Failed to open'))) {
      return '加载失败, 请尝试更换其他视频来源';
    }
    return null;
  }
}

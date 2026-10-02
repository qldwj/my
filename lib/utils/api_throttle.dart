import 'dart:async';

/// 🆕 API 请求节流器
/// 服务器 Kangle 防 CC 有频率限制：App 并发/快速多发请求会触发
/// 401 + JS 验证页(cbk_var)，导致 JSON 解析失败。
/// 这里对自有后端的所有 API 请求做全局串行 + 最小间隔，避免触发限流。
class ApiThrottle {
  static Future<void> _queue = Future.value();
  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minGap = Duration(milliseconds: 200);

  static Future<void> wait() async {
    // 最小间隔
    final now = DateTime.now();
    final sinceLast = now.difference(_lastCall);
    if (sinceLast < _minGap) {
      await Future.delayed(_minGap - sinceLast);
    }
    // 全局串行：上一个请求完成后再发下一个
    final prev = _queue;
    final completer = Completer<void>();
    _queue = completer.future;
    await prev;
    _lastCall = DateTime.now();
    completer.complete();
  }
}

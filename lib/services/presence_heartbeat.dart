import 'dart:async';

import 'package:yhdm/services/auth_service.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/presence_service.dart';

/// App 级在线心跳：负责维持「在线 / 离线」状态
///
/// 与播放页心跳互补：
/// - 本类在 App 启动后常驻，每 60s 上报一次 status=online
/// - 播放页 PlayerItem 会额外上报 status=playing + 当前 subject
/// - 退播放页时 PlayerItem 会主动上报一次 status=online
/// - App 进程被杀后，服务端 last_seen 超 180s 自动判为 offline
class PresenceHeartbeat {
  PresenceHeartbeat._();

  static final PresenceHeartbeat instance = PresenceHeartbeat._();

  static const Duration _interval = Duration(seconds: 60);
  static const Duration _reconnectAfter = Duration(seconds: 15);

  Timer? _timer;
  bool _active = false;

  /// App 启动后由 main() 调用一次。未登录或开关关闭直接返回。
  /// 已登录会立即上报一次并启动定时。
  void startIfLoggedIn() {
    if (AuthService.getLocalToken() == null) return;
    start();
  }

  /// 登录成功 / 换号后调用（AuthService.onLoginChanged 挂这里）
  void start() {
    if (_active) return;
    if (AuthService.getLocalToken() == null) return;
    if (!PresenceService.enabled) return;
    _active = true;
    _scheduleNext(const Duration(milliseconds: 500));
  }

  /// 登出后调用
  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 每次登录状态变化 / 开关变化后：本地 token 消失或换成新的，都重启一次
  void refresh() {
    stop();
    if (AuthService.isLoggedIn && PresenceService.enabled) start();
  }

  void _scheduleNext(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _tick);
  }

  Future<void> _tick() async {
    if (!_active) return;
    if (AuthService.getLocalToken() == null) {
      stop();
      return;
    }
    if (!PresenceService.enabled) {
      stop();
      return;
    }
    try {
      await PresenceService.beatOnline();
    } catch (e) {
      KazumiLogger().w('Presence heartbeat tick failed', forceLog: true);
    } finally {
      _scheduleNext(_interval);
    }
  }
}

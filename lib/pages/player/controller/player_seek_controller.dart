import 'package:yhdm/pages/player/controller/player_danmaku_controller.dart';
import 'package:yhdm/pages/player/controller/player_playback_controller.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/utils/async_serial_queue.dart';

class _InteractiveSeekSession {
  _InteractiveSeekSession(this.pauseCompleted, this.target)
      : initialPosition = target;

  final Future<void> pauseCompleted;
  Duration target;
  Future<bool>? commit;

  /// 取消拖动时回到这里（预览移动过，但没有真正 seek）
  final Duration initialPosition;
}

class PlayerSeekController {
  PlayerSeekController({
    required PlayerPlaybackController playback,
    required PlayerDanmakuController danmaku,
    required Future<void> Function({bool enableSync}) pause,
    required Future<void> Function({bool enableSync}) play,
    required Future<void> Function(bool enableSync) onSeekCompleted,
  })  : _playback = playback,
        _danmaku = danmaku,
        _pause = pause,
        _play = play,
        _onSeekCompleted = onSeekCompleted;

  final PlayerPlaybackController _playback;
  final PlayerDanmakuController _danmaku;
  final Future<void> Function({bool enableSync}) _pause;
  final Future<void> Function({bool enableSync}) _play;
  final Future<void> Function(bool enableSync) _onSeekCompleted;

  final AsyncSerialQueue _seekQueue = AsyncSerialQueue();
  _InteractiveSeekSession? _interactiveSession;

  bool get hasActiveInteractiveSeek => _interactiveSession != null;

  Future<void> seekTo(
    Duration target, {
    bool enableSync = true,
  }) {
    final player = _playback.mediaPlayer;
    if (player == null) {
      return Future<void>.value();
    }

    final normalizedTarget = _normalize(target);
    _playback.currentPosition = normalizedTarget;
    _danmaku.clearAndInvalidateScheduledDanmakus();

    return _seekQueue.run(() async {
      if (!_playback.isCurrentPlayer(player)) {
        return;
      }
      try {
        await player.seek(normalizedTarget);
      } catch (_) {
        return;
      }
      if (!_playback.isCurrentPlayer(player)) {
        return;
      }
      try {
        await _onSeekCompleted(enableSync);
      } catch (e) {
        // Callers often drop this future; it must not complete with an error.
        KazumiLogger()
            .w('PlayerSeekController: seek completion failed', error: e);
      }
    });
  }

  Future<void> seekBy(
    Duration offset, {
    bool enableSync = true,
  }) =>
      seekTo(
        _playback.currentPosition + offset,
        enableSync: enableSync,
      );

  void beginInteractiveSeek() {
    _interactiveSession = _InteractiveSeekSession(
      _pause(enableSync: false),
      _playback.currentPosition,
    );
  }

  bool updateInteractiveSeek(Duration target) {
    final session = _interactiveSession;
    if (session == null) {
      return false;
    }
    session.target = _normalize(target);
    _playback.currentPosition = session.target;
    return true;
  }

  Future<bool> commitInteractiveSeek({bool cancelled = false}) {
    final session = _interactiveSession;
    if (session == null) {
      return Future<bool>.value(false);
    }
    return session.commit ??=
        _commitInteractiveSeek(session, cancelled: cancelled);
  }

  void invalidateInteractiveSeek() {
    _interactiveSession = null;
  }

  Future<bool> _commitInteractiveSeek(
    _InteractiveSeekSession session, {
    required bool cancelled,
  }) async {
    try {
      await session.pauseCompleted;
      if (!_isCurrent(session)) {
        return false;
      }

      if (cancelled) {
        // 只有预览位置变了，取消时不需要真正 seek。
        _playback.currentPosition = session.initialPosition;
      } else {
        await seekTo(session.target);
        if (!_isCurrent(session)) {
          return false;
        }
      }

      await _play(enableSync: false);
      return _isCurrent(session);
    } finally {
      if (_isCurrent(session)) {
        _interactiveSession = null;
      }
    }
  }

  Duration _normalize(Duration target) {
    var milliseconds = target.inMilliseconds;
    if (milliseconds < 0) {
      milliseconds = 0;
    }
    final duration = _playback.duration;
    if (duration > Duration.zero && milliseconds > duration.inMilliseconds) {
      milliseconds = duration.inMilliseconds;
    }
    return Duration(milliseconds: milliseconds);
  }

  bool _isCurrent(_InteractiveSeekSession session) =>
      identical(_interactiveSession, session);

}

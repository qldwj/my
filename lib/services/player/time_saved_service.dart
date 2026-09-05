import 'package:kazumi/services/storage/storage.dart';

/// ⚡ 省时统计：记录跳过的片头/片尾/快进节省的秒数
class TimeSavedService {
  TimeSavedService._();

  /// 本集(会话)累计节省秒数
  static int _sessionSeconds = 0;

  static int get sessionSeconds => _sessionSeconds;

  /// 历史累计节省总秒数
  static int get totalSeconds =>
      GStorage.getSetting(SettingsKeys.timeSavedSeconds);

  static Future<void> add(int seconds) async {
    if (seconds <= 0) return;
    _sessionSeconds += seconds;
    await GStorage.putSetting(
        SettingsKeys.timeSavedSeconds, totalSeconds + seconds);
  }

  static Future<void> resetSession() async {
    _sessionSeconds = 0;
  }
}

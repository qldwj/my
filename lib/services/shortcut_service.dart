import 'package:flutter/services.dart';

/// 桌面快捷方式服务
///
/// 功能：
/// - [pinShortcut]：为某部番创建桌面快捷方式（Android 8+，需用户确认）
/// - [init]：注册快捷方式点击回调（点击后直接播放该番）
class ShortcutService {
  ShortcutService._();

  static const MethodChannel _channel =
      MethodChannel('com.predidit.kazumi/shortcut');

  static void Function(ShortcutPlayParams params)? _onPlay;

  /// 快捷方式点击参数
  static const String _pendingPlayKey = 'kazumi_shortcut_pending';

  /// 初始化：注册回调，处理启动/运行中收到的快捷方式点击
  static void init({required void Function(ShortcutPlayParams) onPlay}) {
    _onPlay = onPlay;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShortcut' && call.arguments is Map) {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _onPlay?.call(ShortcutPlayParams(
          id: int.tryParse(args['id']?.toString() ?? '') ?? 0,
          name: args['name']?.toString() ?? '',
          episode: int.tryParse(args['ep']?.toString() ?? '') ?? 0,
          adapterName: args['adapterName']?.toString() ?? '',
        ));
      }
    });
  }

  /// 为某部番创建桌面快捷方式（返回是否成功触发固定请求）
  static Future<bool> pinShortcut({
    required int id,
    required String name,
    required int episode,
    required String adapterName,
  }) async {
    if (id <= 0) return false;
    try {
      final result = await _channel.invokeMethod<bool>('pinShortcut', {
        'id': id.toString(),
        'name': name,
        'ep': episode,
        'adapterName': adapterName,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// 快捷方式播放参数
class ShortcutPlayParams {
  const ShortcutPlayParams({
    required this.id,
    required this.name,
    required this.episode,
    required this.adapterName,
  });

  final int id;
  final String name;
  final int episode;
  final String adapterName;
}

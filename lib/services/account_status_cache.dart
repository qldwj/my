import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:yhdm/services/auth_service.dart';
import 'package:yhdm/services/storage/settings_keys.dart';
import 'package:yhdm/services/storage/storage.dart';

/// 账号绑定状态的本地缓存（存在 Hive 的 `setting` 盒里）
///
/// 目的：进「我的 / 编辑资料 / 账号绑定」时**先渲染本地缓存**，
/// 不再每次进入都打服务器 `api/v1/login?action=login_status`；
/// 距上次成功拉取超过 [refreshInterval] 才在后台重新拉一次。
///
/// 安全性：缓存里带 token 的 sha256 前 16 位作为归属签名，
/// 换账号 / 退出登录 / 解绑后立即失效，不会串号。
class AccountStatusCache {
  AccountStatusCache._();

  /// 距上次拉取超过这个时间才再打服务器
  static const Duration refreshInterval = Duration(minutes: 5);

  /// 归属签名（不落明文 token）
  static String _sig() {
    final token = AuthService.getLocalToken() ?? '';
    if (token.isEmpty) return '';
    return sha256.convert(utf8.encode(token)).toString().substring(0, 16);
  }

  /// 读到可用缓存则返回服务器原始 status map，否则 null
  static Map<String, dynamic>? readStatus() {
    try {
      final raw = GStorage.getSetting<String>(SettingsKeys.accountStatusCache);
      final at = GStorage.getSetting<int>(SettingsKeys.accountStatusAt);
      if (raw.isEmpty || at == 0) return null;
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      if (j['sig'] != _sig()) return null; // 换账号 → 作废
      final s = j['status'];
      if (s is Map) return Map<String, dynamic>.from(s);
    } catch (_) {}
    return null;
  }

  /// 是否该再去服务器拉一次
  static bool get shouldRefresh {
    try {
      final at = GStorage.getSetting<int>(SettingsKeys.accountStatusAt);
      if (at == 0) return true;
      return DateTime.now().millisecondsSinceEpoch - at >
          refreshInterval.inMilliseconds;
    } catch (_) {
      return true;
    }
  }

  static Future<void> saveStatus(Map<String, dynamic> status) async {
    try {
      final body = jsonEncode({'sig': _sig(), 'status': status});
      await GStorage.putSetting<String>(SettingsKeys.accountStatusCache, body);
      await GStorage.putSetting<int>(
        SettingsKeys.accountStatusAt,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await GStorage.putSetting<String>(SettingsKeys.accountStatusCache, '');
      await GStorage.putSetting<int>(SettingsKeys.accountStatusAt, 0);
    } catch (_) {}
  }
}

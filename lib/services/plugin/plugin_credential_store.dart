import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 插件登录凭证持久化存储
///
/// 保存账号密码（仅当用户勾选「记住密码」时），用于 Cookie 过期后
/// 自动调用 /api/auth/login 重新获取 token，用户无需重复登录。
class PluginCredentialStore {
  PluginCredentialStore._();
  static final PluginCredentialStore instance = PluginCredentialStore._();

  /// 保存账号密码
  Future<void> save(String pluginName, String username, String password) async {
    try {
      await GStorage.putStringListSettingByName(
        'plugin_cred_$pluginName', [username, password]);
      KazumiLogger().i('[CredentialStore] 已保存 $pluginName 账号密码');
    } catch (e) {
      KazumiLogger().e('[CredentialStore] 保存失败', error: e);
    }
  }

  /// 读取账号密码（返回 null 表示未保存）
  (String, String)? load(String pluginName) {
    try {
      final list = GStorage.getStringListSettingByName('plugin_cred_$pluginName');
      if (list.length >= 2 && list[0].isNotEmpty && list[1].isNotEmpty) {
        return (list[0], list[1]);
      }
    } catch (_) {}
    return null;
  }

  /// 清除账号密码
  Future<void> clear(String pluginName) async {
    try {
      await GStorage.putStringListSettingByName('plugin_cred_$pluginName', ['', '']);
    } catch (_) {}
  }
}

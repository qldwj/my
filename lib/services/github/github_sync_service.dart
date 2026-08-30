import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/logging/logger.dart';

/// GitHub 云同步服务
/// 用 GitHub 仓库存储用户数据（收藏/历史/设置）
class GitHubSyncService {
  static const String tokenKey = 'github_cloud_token';
  static const String repoKey = 'github_cloud_repo';
  static const String usernameKey = 'github_cloud_username';
  static const String defaultRepo = 'yhdmjson';

  /// 获取 GitHub Token
  static String? get token => GStorage._setting.get(tokenKey) ?? "";
  static Future<void> saveToken(String t) async => await GStorage._setting.put(tokenKey, t);
  static Future<void> clearToken() async => await GStorage.putSetting(tokenKey, '');

  /// 获取仓库名
  static String get repo => GStorage._setting.get(repoKey) ?? defaultRepo ?? defaultRepo;
  static Future<void> saveRepo(String r) async => await GStorage._setting.put(repoKey, r);

  /// 获取 GitHub 用户名（带缓存）
  static String? _username;
  static Future<String> getUsername() async {
    if (_username != null) return _username!;
    if (token == null) return '';
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        _username = jsonDecode(res.body)['login'];
        return _username!;
      }
    } catch (_) {}
    return '';
  }

  static bool get isConfigured => token != null && token!.isNotEmpty;

  /// 🆕 创建仓库（幂等，已存在跳过）
  static Future<bool> ensureRepo() async {
    if (!isConfigured) return false;
    final username = await getUsername();
    if (username.isEmpty) return false;
    try {
      final res = await http.post(
        Uri.parse('https://api.github.com/user/repos'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        body: jsonEncode({'name': repo, 'description': '樱花动漫云端数据', 'private': true, 'auto_init': true}),
      );
      return res.statusCode == 201 || res.statusCode == 422;
    } catch (e) {
      KazumiLogger().e('GitHub: ensureRepo error', error: e);
      return false;
    }
  }

  /// 🆕 上传文件到仓库
  static Future<bool> uploadFile(String path, String content) async {
    if (!isConfigured) return false;
    final username = await getUsername();
    if (username.isEmpty) return false;
    try {
      // 获取现有 SHA（更新用）
      String? sha;
      final getRes = await http.get(
        Uri.parse('https://api.github.com/repos/$username/$repo/contents/$path'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/vnd.github+json'},
      );
      if (getRes.statusCode == 200) {
        sha = jsonDecode(getRes.body)['sha'];
      }
      final body = {'message': 'Update $path', 'content': base64Encode(utf8.encode(content))};
      if (sha != null) body['sha'] = sha;
      final res = await http.put(
        Uri.parse('https://api.github.com/repos/$username/$repo/contents/$path'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'},
        body: jsonEncode(body),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      KazumiLogger().e('GitHub: upload error', error: e);
      return false;
    }
  }

  /// 🆕 下载文件
  static Future<String?> downloadFile(String path) async {
    if (!isConfigured) return null;
    final username = await getUsername();
    if (username.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$username/$repo/contents/$path'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/vnd.github+json'},
      );
      if (res.statusCode == 200) {
        return utf8.decode(base64Decode(jsonDecode(res.body)['content']));
      }
      return null;
    } catch (e) {
      KazumiLogger().e('GitHub: download error', error: e);
      return null;
    }
  }

  /// 🆕 同步到云端
  static Future<Map<String, bool>> syncToCloud() async {
    final results = <String, bool>{};
    if (!isConfigured) return results;
    await ensureRepo();

    // 同步收藏
    try {
      final collect = GStorage.collectibles.values.map((c) => {
        'id': c.bangumiItem.id,
        'name': c.bangumiItem.nameCn.isNotEmpty ? c.bangumiItem.nameCn : c.bangumiItem.name,
        'type': c.type,
        'time': c.time,
      }).toList();
      results['collect'] = await uploadFile('collect.json', jsonEncode(collect));
    } catch (_) { results['collect'] = false; }

    // 同步历史
    try {
      final history = GStorage.histories.values.map((h) => {
        'id': h.bangumiItem.id,
        'name': h.bangumiItem.nameCn.isNotEmpty ? h.bangumiItem.nameCn : h.bangumiItem.name,
        'episode': h.progresses.isNotEmpty ? h.progresses.values.last.episode : 0,
        'time': h.time,
      }).toList();
      results['history'] = await uploadFile('history.json', jsonEncode(history));
    } catch (_) { results['history'] = false; }

    // 同步设置
    try {
      final settings = {
        'speed': GStorage.getSetting(SettingsKeys.defaultPlaySpeed),
        'volume': GStorage.getSetting(SettingsKeys.defaultVolume),
      };
      results['settings'] = await uploadFile('settings.json', jsonEncode(settings));
    } catch (_) { results['settings'] = false; }

    return results;
  }

  /// 🆕 从云端恢复
  static Future<Map<String, bool>> syncFromCloud() async {
    final results = <String, bool>{};
    if (!isConfigured) return results;

    final collectJson = await downloadFile('collect.json');
    if (collectJson != null) {
      results['collect'] = true;
      KazumiLogger().i('GitHub: downloaded collect.json');
    }

    final historyJson = await downloadFile('history.json');
    if (historyJson != null) {
      results['history'] = true;
      KazumiLogger().i('GitHub: downloaded history.json');
    }

    return results;
  }

  /// 获取最后同步时间
  static int get lastSync {
    try {
      final v = GStorage.getSetting(SettingsKeys.githubCloudLastSync);
      return (v is int) ? v : 0;
    } catch (_) { return 0; }
  }
  static Future<void> updateLastSync() async => await GStorage.putSetting(SettingsKeys.githubCloudLastSync, DateTime.now().millisecondsSinceEpoch);
}

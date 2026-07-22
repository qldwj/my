import 'package:flutter_modular/flutter_modular.dart';
import 'package:dio/dio.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

class OfficialSyncService {
  static final OfficialSyncService instance = OfficialSyncService._internal();
  OfficialSyncService._internal();

  late Dio _dio;
  bool initialized = false;
  String? _token;
  String? _serverUrl;

  Future<void> init() async {
    _serverUrl = GStorage.getSetting(SettingsKeys.officialSyncServerUrl);
    _token = GStorage.getSetting(SettingsKeys.officialSyncToken);

    if (_serverUrl == null || _serverUrl!.isEmpty || _token == null || _token!.isEmpty) {
      initialized = false;
      return;
    }

    _dio = Dio(BaseOptions(
      baseUrl: _serverUrl!,
      headers: {
        "Authorization": "Bearer $_token",
        "Content-Type": "application/json",
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    initialized = true;
    KazumiLogger().d("官方同步服务初始化完成，服务器：$_serverUrl");
  }

  // 连通性测试
  Future<void> ping() async {
    if (!initialized) await init();
    if (!initialized) throw Exception("未配置服务器或登录账号");
    await _dio.get("/api/ping");
  }

  // 注册账号
  Future<void> register(String username, String password) async {
    final res = await _dio.post("/api/auth/register", data: {
      "username": username,
      "password": password,
    });
    final token = res.data["token"];
    await GStorage.putSetting(SettingsKeys.officialSyncUsername, username);
    await GStorage.putSetting(SettingsKeys.officialSyncPassword, password);
    await GStorage.putSetting(SettingsKeys.officialSyncToken, token);
    _token = token;
    initialized = true;
  }

  // 登录账号
  Future<void> login(String username, String password) async {
    final res = await _dio.post("/api/auth/login", data: {
      "username": username,
      "password": password,
    });
    final token = res.data["token"];
    await GStorage.putSetting(SettingsKeys.officialSyncUsername, username);
    await GStorage.putSetting(SettingsKeys.officialSyncPassword, password);
    await GStorage.putSetting(SettingsKeys.officialSyncToken, token);
    _token = token;
    initialized = true;
  }

  // 单个收藏新增/更新同步
  Future<bool> syncSingleCollect(int bangumiId, int type) async {
    if (!initialized) await init();
    await _dio.post("/api/collect/sync", data: {
      "bangumi_id": bangumiId,
      "collect_type": type,
    });
    return true;
  }

  // 删除收藏同步
  Future<void> syncDeleteCollect(int bangumiId) async {
    if (!initialized) await init();
    await _dio.delete("/api/collect/$bangumiId");
  }

  // 批量拉取云端收藏
  Future<void> syncAllCollectibles() async {
    if (!initialized) await init();
  }

  // 退出登录
  Future<void> logout() async {
    await GStorage.putSetting(SettingsKeys.officialSyncToken, "");
    await GStorage.putSetting(SettingsKeys.officialSyncUsername, "");
    _token = null;
    initialized = false;
  }
}

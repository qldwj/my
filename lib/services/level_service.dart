import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kazumi/services/auth_service.dart';

/// 徽章
class LevelBadge {
  final String id;
  final String name;
  final String icon;
  final String desc;
  final bool unlocked;

  LevelBadge.fromJson(Map<String, dynamic> j)
      : id = j['id']?.toString() ?? '',
        name = j['name']?.toString() ?? '',
        icon = j['icon']?.toString() ?? '🏅',
        desc = j['desc']?.toString() ?? '',
        unlocked = j['unlocked'] == true;
}

/// 等级信息
class LevelInfo {
  final int level;
  final int exp;
  final int cur;
  final int next;
  final int progress; // 0-100
  final List<LevelBadge> badges;

  LevelInfo.fromJson(Map<String, dynamic> j)
      : level = (j['level'] as num?)?.toInt() ?? 1,
        exp = (j['exp'] as num?)?.toInt() ?? 0,
        cur = (j['cur'] as num?)?.toInt() ?? 0,
        next = (j['next'] as num?)?.toInt() ?? 20,
        progress = (j['progress'] as num?)?.toInt() ?? 0,
        badges = ((j['badges'] as List?) ?? const [])
            .map((e) => LevelBadge.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

  bool get isMax => next == null || next == 0;
}

/// 等级服务（对接 /api/v1/exp.php）
class LevelService {
  static const String api = 'https://qlyyz.xyz/api/v1/exp.php';

  /// 等级图标（内置，1-6 级）
  static const Map<int, String> levelIcons = {
    1: 'https://www.miyohost.cn/api/apps/app_muormwax8157a7/files/download?path=ic_lv1.png',
    2: 'https://www.miyohost.cn/api/apps/app_muormwax8157a7/files/download?path=ic_lv2.png',
    3: 'https://www.miyohost.cn/api/apps/app_muormwax8157a7/files/download?path=ic_lv3.png',
    4: 'https://www.miyohost.cn/api/apps/app_muormwax8157a7/files/download?path=ic_lv4.png',
    5: 'https://www.miyohost.cn/api/apps/app_muormwax8157a7/files/download?path=ic_lv5.png',
    6: 'https://www.miyohost.cn/api/apps/app_muormwax8157a7/files/download?path=ic_lv6.png',
  };

  static String levelIconUrl(int level) => levelIcons[level] ?? levelIcons[1]!;

  /// 获取等级信息（collectCount 为 -1 时不更新收藏数）
  static Future<LevelInfo?> fetch({int collectCount = -1}) async {
    final token = AuthService.getLocalToken();
    if (token == null) return null;
    try {
      final res = await http.get(Uri.parse(
          '$api?action=get&token=$token&collect_count=$collectCount'));
      final j = jsonDecode(res.body);
      if (j is Map && j['success'] == true) return LevelInfo.fromJson(j);
    } catch (_) {}
    return null;
  }

  /// 增加经验（source: checkin / watch / comment）
  static Future<Map<String, dynamic>?> addExp(String source) async {
    final token = AuthService.getLocalToken();
    if (token == null) return null;
    try {
      final res = await http.post(Uri.parse('$api?action=add_exp'),
          body: {'token': token, 'source': source});
      final j = jsonDecode(res.body);
      if (j is Map && j['success'] == true) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return null;
  }
}

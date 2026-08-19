import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/my/chat_page.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 追番更新提醒（新番推送通知）
///
/// 原理：
/// 1. 遍历收藏中「在看 / 想看」的番剧
/// 2. 通过 Bangumi API 获取剧集列表（含 airdate 放送日期），统计
///    「已放送的最大普通集数」（airdate <= 今天 且 30 天内仍有放送）
/// 3. 与本地历史记录中的最大已看集数对比，存在未看新集则聚合推送
/// 4. 点击通知直达番剧详情页
///
/// 检查时机：App 启动时一次 + 每小时定时器检查（间隔由设置控制：8/12/24h）
/// 说明：仅 App 进程存活期间自动检查；如需系统级后台定时任务，
/// 可在此基础上接入 workmanager / 前台服务。
class AnimeUpdateNotificationService {
  AnimeUpdateNotificationService._();

  static const String channelId = 'kazumi_anime_update_channel';
  static const String channelName = '追番提醒';
  static const String channelDescription = '收藏番剧更新时推送通知';

  static FlutterLocalNotificationsPlugin? _plugin;
  static Timer? _timer;
  static bool _initialized = false;
  static int _nextNotificationId = 1;

  /// 应用启动时调用：初始化插件 + 请求权限 + 启动定时检查
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _plugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin!.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
      // Android 13+ 需要 POST_NOTIFICATIONS 运行时权限
      if (Platform.isAndroid) {
        await _plugin!
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      // 每小时检查一次是否到达检查间隔
      _timer ??= Timer.periodic(
        const Duration(hours: 1),
        (_) => unawaited(checkForUpdates()),
      );
      // 启动后延迟 8 秒做一次检查（避开启动高峰期）
      Timer(const Duration(seconds: 8), () {
        unawaited(checkForUpdates());
      });
      KazumiLogger().i('AnimeUpdateNotificationService: initialized');
    } catch (e) {
      KazumiLogger().w('AnimeUpdateNotificationService: init failed', error: e);
    }
  }

  /// 发送一条测试通知（验证通知通道是否正常）
  static Future<void> sendTestNotification() async {
    await showNotification(
      title: '🔔 追番提醒测试',
      body: '这是一条测试通知，说明通知通道已正常工作。',
      payload: 'test',
    );
  }

  /// 🆕 通用通知发送（追番提醒 / 下载完成等共用同一通知通道）
  ///
  /// [payload] 用于通知点击回调（见 [_onNotificationTap]）。
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (_plugin == null) {
      await init();
    }
    if (_plugin == null) return;
    try {
      // 🆕 桌面角标：iOS 生效；Android 需桌面启动器支持（部分机型不显示）
      final badgeEnabled = GStorage.getSetting(SettingsKeys.notificationBadge);
      await _plugin!.show(
        _nextNotificationId++,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            // 🔧 通知带提示音（微信式提醒；由系统通知声播放）
            playSound: true,
            category: AndroidNotificationCategory.recommendation,
          ),
          iOS: DarwinNotificationDetails(
            badgeNumber: badgeEnabled ? 1 : 0,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      KazumiLogger().w(
          'NotificationService: show notification failed',
          error: e);
    }
  }

  /// 检查收藏番剧是否有未看新集。
  /// [manual] = true 时忽略总开关与检查间隔（设置页"立即检查"）。
  static Future<void> checkForUpdates({bool manual = false}) async {
    if (_plugin == null) return;
    final enabled = GStorage.getSetting(SettingsKeys.animeUpdateNotify);
    if (!enabled && !manual) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (!manual) {
      final last = GStorage.getSetting(SettingsKeys.animeUpdateLastCheck);
      final intervalHours =
          GStorage.getSetting(SettingsKeys.animeUpdateCheckIntervalHours);
      if (last > 0 && now - last < intervalHours * 3600 * 1000) return;
    }

    final updates = await _collectUpdates();
    if (updates.isNotEmpty) {
      await _showUpdateNotification(updates);
    }
    await GStorage.putSetting(SettingsKeys.animeUpdateLastCheck, now);
    KazumiLogger().i(
        'AnimeUpdateNotificationService: checked, found ${updates.length} updates');
    // 🆕 续作/换季提醒（独立开关，随检查频率执行）
    if (GStorage.getSetting(SettingsKeys.sequelNotify)) {
      await _checkSequels();
    }
  }

  /// 🆕 续作/换季提醒：收藏番剧的续作（relation 含"续"）在 45 天内开播时通知
  static Future<void> _checkSequels() async {
    final collectibles = GStorage.collectibles.values
        .where((c) => c.type == 1 || c.type == 2) // 在看 / 想看
        .take(10)
        .toList();
    if (collectibles.isEmpty) return;

    final today = DateTime.now();
    final horizon = today.add(const Duration(days: 45));
    final notices = <String>[];

    for (final c in collectibles) {
      try {
        final relations =
            await BangumiApi.getRelatedSubjects(c.bangumiItem.id);
        for (final relation in relations) {
          if (!_isSequelRelation(relation.relation)) continue;
          final info = await BangumiApi.getBangumiInfoByID(relation.id);
          if (info == null) continue;
          final air = DateTime.tryParse(info.airDate);
          if (air == null) continue;
          if (air.isAfter(today) && !air.isAfter(horizon)) {
            final name = c.bangumiItem.nameCn.isNotEmpty
                ? c.bangumiItem.nameCn
                : c.bangumiItem.name;
            final sequelName =
                relation.nameCn.isNotEmpty ? relation.nameCn : relation.name;
            notices.add('《$name》续作《$sequelName》${info.airDate} 开播');
          }
        }
      } catch (_) {
        // 单部失败跳过
      }
    }

    if (notices.isNotEmpty) {
      await showNotification(
        title: '🎬 续作开播提醒',
        body: notices.take(3).join('\n'),
        payload: 'sequel',
      );
    }
  }

  /// 判断关联关系是否为续作
  static bool _isSequelRelation(String relation) {
    final r = relation.toLowerCase();
    return r.contains('续') || r.contains('sequel');
  }

  /// 收集未看新集（按最近放送日期排序）
  static Future<List<_AnimeUpdate>> _collectUpdates() async {
    final onlyWatching = GStorage.getSetting(SettingsKeys.animeUpdateOnlyWatching);
    final collectibles = GStorage.collectibles.values.where((c) {
      if (onlyWatching) return c.type == 1; // 在看
      return c.type == 1 || c.type == 2; // 在看 / 想看
    }).toList();
    if (collectibles.isEmpty) return [];

    final today = DateTime.now();
    final cutoff = today.subtract(const Duration(days: 30));
    final histories = HistoryRepository().getAllHistories();
    final updates = <_AnimeUpdate>[];

    // 并行拉取剧集列表，控制并发
    const concurrency = 5;
    for (var i = 0; i < collectibles.length; i += concurrency) {
      final batch = collectibles.sublist(
        i,
        i + concurrency > collectibles.length
            ? collectibles.length
            : i + concurrency,
      );
      final results = await Future.wait(batch.map((c) async {
        final item = c.bangumiItem;
        try {
          final episodes = await BangumiApi.getBangumiEpisodesByID(item.id);
          final aired = _computeAiredMax(episodes, today, cutoff);
          if (aired == null) return null;
          // 本地已看最大集数（跨插件统计）
          var watchedMax = 0;
          for (final h in histories) {
            if (h.bangumiItem.id != item.id) continue;
            for (final ep in h.progresses.keys) {
              if (ep > watchedMax) watchedMax = ep;
            }
            for (final p in h.progresses.values) {
              if (p.episode > watchedMax) watchedMax = p.episode;
            }
          }
          if (aired.airedMax <= watchedMax) return null;
          return _AnimeUpdate(
            subjectId: item.id,
            name: item.nameCn.isNotEmpty ? item.nameCn : item.name,
            airedMax: aired.airedMax,
            watchedMax: watchedMax,
            lastAirDate: aired.lastAirDate,
          );
        } catch (e) {
          KazumiLogger().w(
              'AnimeUpdateNotificationService: fetch episodes failed for ${item.id}',
              error: e);
          return null;
        }
      }));
      updates.addAll(results.whereType<_AnimeUpdate>());
    }

    updates.sort((a, b) => b.lastAirDate.compareTo(a.lastAirDate));
    return updates;
  }

  /// 计算已放送最大普通集数。
  /// 返回 null 表示该番没有在 30 天内有放送行为的普通集（老番跳过）。
  static _AiredInfo? _computeAiredMax(
    List<EpisodeInfo> episodes,
    DateTime today,
    DateTime cutoff,
  ) {
    int airedMax = 0;
    DateTime? lastAirDate;
    for (final ep in episodes) {
      if (ep.type != 0) continue; // 只看普通集（type=0）
      final d = DateTime.tryParse(ep.airdate);
      if (d == null) continue;
      if (d.isAfter(today)) continue; // 未放送
      final n = ep.episode is int ? ep.episode.toInt() : ep.episode.round();
      if (n > airedMax) airedMax = n;
      if (lastAirDate == null || d.isAfter(lastAirDate)) lastAirDate = d;
    }
    if (airedMax <= 0 || lastAirDate == null) return null;
    if (lastAirDate.isBefore(cutoff)) return null; // 30 天内无放送
    return _AiredInfo(airedMax: airedMax, lastAirDate: lastAirDate);
  }

  /// 聚合推送（最多展示前 3 部）
  static Future<void> _showUpdateNotification(List<_AnimeUpdate> updates) async {
    if (_plugin == null) return;
    final top = updates.take(3).toList();
    final title = updates.length == 1
        ? '《${top.first.name}》更新到第 ${top.first.airedMax} 集'
        : '${updates.length} 部番剧有更新';
    final body = top
        .map((u) => '《${u.name}》更新到第 ${u.airedMax} 集'
            '（你看到第 ${u.watchedMax} 集）')
        .join('\n');
    final payload = top.first.subjectId.toString();
    await _plugin!.show(
      _nextNotificationId++,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.recommendation,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  /// 点击通知：打开番剧详情页 / 下载页 / 好友聊天
  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    if (payload == 'download') {
      // 🆕 下载完成通知 → 打开下载管理页
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final context = rootNavigatorKey.currentContext;
          if (context == null || !context.mounted) return;
          final path = context.routeState(listen: false).uri.path;
          if (path.contains('/download')) return;
          Navigator.of(context).pushNamed('/settings/download/');
        } catch (e) {
          KazumiLogger().w(
              'Notification: failed to navigate to download page',
              error: e);
        }
      });
      return;
    }
    // 🆕 好友聊天通知 → 打开与该好友的聊天
    if (payload.startsWith('chat:')) {
      final uid = payload.substring(5);
      Future.delayed(const Duration(milliseconds: 300), () async {
        try {
          final convs = await SocialService.chatRecent();
          final matches = convs.where((c) => c.uid == uid).toList();
          if (matches.isEmpty) return;
          final conv = matches.first;
          final context = rootNavigatorKey.currentContext;
          if (context == null || !context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatPage(
              friend: SocialProfile(
                uid: conv.uid,
                nickname: conv.nickname,
                avatar: conv.avatar,
              ),
            ),
          ));
        } catch (e) {
          KazumiLogger().w('Notification: failed to open chat', error: e);
        }
      });
      return;
    }
    final id = int.tryParse(payload);
    if (id == null || id <= 0) return;
    unawaited(_openDetail(id));
  }

  static Future<void> _openDetail(int id) async {
    try {
      final item = await BangumiApi.getBangumiInfoByID(id);
      if (item == null) return;
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      Navigator.of(context).pushNamed('/info/', arguments: item);
    } catch (e) {
      KazumiLogger().e(
          'AnimeUpdateNotificationService: open detail failed',
          error: e);
    }
  }
}

class _AnimeUpdate {
  const _AnimeUpdate({
    required this.subjectId,
    required this.name,
    required this.airedMax,
    required this.watchedMax,
    required this.lastAirDate,
  });

  final int subjectId;
  final String name;
  final int airedMax;
  final int watchedMax;
  final DateTime lastAirDate;
}

class _AiredInfo {
  const _AiredInfo({required this.airedMax, required this.lastAirDate});

  final int airedMax;
  final DateTime lastAirDate;
}

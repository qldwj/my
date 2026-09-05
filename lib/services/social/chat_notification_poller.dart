import 'dart:async';

import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/notification/anime_update_notification_service.dart';
import 'package:kazumi/services/social/social_service.dart';

/// 好友聊天消息通知（前台轮询）
///
/// App 运行期间每 30 秒拉取最近会话，发现新消息（对方发的、未读）时弹系统通知。
/// 点击通知直达聊天（payload: chat:<uid>）。
///
/// 说明：仅在 App 前台运行时生效；如需锁屏/后台通知需接入
/// workmanager 系统级后台任务（后续可加）。
class ChatNotificationPoller {
  ChatNotificationPoller._();

  static Timer? _timer;
  static final Map<String, int> _lastNotifiedId = {};

  static void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_poll());
    });
    // 启动后立即轮询一次
    unawaited(_poll());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _poll() async {
    if (!AuthService.isLoggedIn) return;
    try {
      final convs = await SocialService.chatRecent();
      for (final c in convs) {
        // 自己发的消息不通知
        final lastId = _lastNotifiedId[c.uid];
        if (lastId != null && c.lastId <= lastId) continue;
        _lastNotifiedId[c.uid] = c.lastId;
        // 已读（聊天页打开过）则不打扰
        if (SocialService.isRead(c.uid, c.lastId)) continue;
        await AnimeUpdateNotificationService.showNotification(
          title: c.nickname,
          body: _preview(c),
          payload: 'chat:${c.uid}',
        );
      }
    } catch (e) {
      KazumiLogger().w('ChatPoller: poll failed', error: e);
    }
  }

  static String _preview(SocialConversation c) {
    switch (c.lastType) {
      case 'emoji':
        return '[表情] ${c.lastContent}';
      case 'anime':
        return '[番剧分享] ${c.lastContent}';
      case 'rule':
        return '[规则分享] ${c.lastContent}';
      default:
        return c.lastContent;
    }
  }
}

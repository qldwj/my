import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/my/chat_page.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 全局好友消息横幅提醒
///
/// - App 前台时每 60 秒轮询好友新消息
/// - 除播放页（/video/）外，任何页面顶部弹出横幅（头像 + 昵称 + 消息）
/// - 点击横幅 → 进入与该好友的聊天
/// - 播放页永不弹横幅（避免打扰观看）
class ChatBannerService {
  ChatBannerService._();

  static Timer? _timer;
  static bool _started = false;
  static bool _bannerShowing = false;
  static final Set<int> _notifiedIds = {};

  /// 启动全局轮询（App 启动时调用一次）
  static void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_poll());
    });
  }

  static void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _poll() async {
    // 开关关闭则跳过
    if (!GStorage.getSetting(SettingsKeys.chatGlobalBanner)) return;
    // 播放页不弹
    if (_isOnVideoPage()) return;

    try {
      final convs = await SocialService.chatRecent();
      for (final c in convs) {
        if (c.lastId <= 0 || _notifiedIds.contains(c.lastId)) continue;
        final unread = SocialService.unreadOf(c);
        if (unread <= 0) continue;
        _notifiedIds.add(c.lastId);
        if (_notifiedIds.length > 200) _notifiedIds.clear();
        _showBanner(c);
        break; // 每次只弹一条，避免刷屏
      }
    } catch (e) {
      KazumiLogger().w('ChatBanner: poll failed', error: e);
    }
  }

  /// 当前是否在播放页（播放页永不弹横幅）
  static bool _isOnVideoPage() {
    try {
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return false;
      final path = context.routeState(listen: false).uri.path;
      return path.contains('/video') || path.contains('/player');
    } catch (_) {
      return false;
    }
  }

  /// 顶部横幅（Overlay 插入）
  static void _showBanner(SocialConversation conv) {
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted || _bannerShowing) return;
    _bannerShowing = true;

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (ctx) => _ChatBanner(
        conversation: conv,
        onTap: () {
          entry?.remove();
          _bannerShowing = false;
          _openChat(conv);
        },
        onClose: () {
          entry?.remove();
          _bannerShowing = false;
        },
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Overlay.of(context, rootOverlay: true).insert(entry!);
        // 6 秒后自动消失
        Timer(const Duration(seconds: 6), () {
          entry?.remove();
          _bannerShowing = false;
        });
      } catch (_) {
        _bannerShowing = false;
      }
    });
  }

  static Future<void> _openChat(SocialConversation conv) async {
    try {
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      // 标记已读
      if (conv.lastId > 0) {
        await SocialService.markRead(conv.uid, conv.lastId);
      }
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            friend: SocialProfile(
              uid: conv.uid,
              nickname: conv.nickname,
              avatar: conv.avatar,
            ),
          ),
        ),
      );
    } catch (e) {
      KazumiLogger().w('ChatBanner: open chat failed', error: e);
    }
  }
}

/// 顶部消息横幅（头像 + 昵称 + 消息预览）
class _ChatBanner extends StatelessWidget {
  const _ChatBanner({
    required this.conversation,
    required this.onTap,
    required this.onClose,
  });

  final SocialConversation conversation;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(14),
        color: colorScheme.inverseSurface,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: conversation.avatar.isNotEmpty
                        ? NetworkImgLayer(
                            width: 36,
                            height: 36,
                            src: SocialService.proxiedAvatar(
                                conversation.avatar),
                          )
                        : Icon(Icons.person_rounded,
                            color: colorScheme.onInverseSurface),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        conversation.nickname,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onInverseSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _preview(conversation),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onInverseSurface
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: colorScheme.onInverseSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _preview(SocialConversation c) {
    if (c.lastContent.isEmpty) return '发来一条消息';
    switch (c.lastType) {
      case 'emoji':
        return '发来表情 ${c.lastContent}';
      case 'anime':
        return '分享了一部番剧';
      case 'rule':
        return '分享了一条规则';
      default:
        return c.lastContent;
    }
  }
}

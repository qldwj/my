import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/social/social_service.dart';

/// 选择好友（用于"分享给好友"）
///
/// 弹出底部面板展示好友列表，点击选中回调 [onPicked]。
class FriendPicker {
  FriendPicker._();

  /// 弹出好友选择面板；返回选中的好友（取消返回 null）
  static Future<SocialProfile?> pick(
    BuildContext context, {
    String title = '分享给好友',
  }) async {
    final friends = await SocialService.friendList();
    if (!context.mounted) return null;
    if (friends.isEmpty) {
      KazumiDialog.showToast(message: '还没有好友，先去添加吧');
      return null;
    }
    final selected = await showModalBottomSheet<SocialProfile>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  final f = friends[index];
                  return ListTile(
                    leading: ClipOval(
                      child: NetworkImgLayer(
                          width: 44,
                          height: 44,
                          src: SocialService.proxiedAvatar(f.avatar)),
                    ),
                    title: Text(f.nickname),
                    subtitle: Text('uid: ${f.uid}'),
                    onTap: () => Navigator.pop(ctx, f),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    return selected;
  }

  /// 发送动漫分享
  static Future<bool> shareAnime(
    BuildContext context, {
    required String name,
    required String link,
    String? summary,
  }) async {
    final friend = await pick(context, title: '分享番剧给好友');
    if (friend == null) return false;
    final content = '🎬 $name\n$link';
    final error = await SocialService.sendMessage(
      toUid: friend.uid,
      type: 'anime',
      content: content,
    );
    if (!context.mounted) return false;
    KazumiDialog.showToast(
        message: error == null ? '✅ 已分享给 ${friend.nickname}' : '❌ $error');
    return error == null;
  }

  /// 发送规则分享
  static Future<bool> shareRule(
    BuildContext context, {
    required String ruleName,
    required String content,
  }) async {
    final friend = await pick(context, title: '分享规则给好友');
    if (friend == null) return false;
    final message = '🧩 $ruleName\n$content';
    final error = await SocialService.sendMessage(
      toUid: friend.uid,
      type: 'rule',
      content: message,
    );
    if (!context.mounted) return false;
    KazumiDialog.showToast(
        message: error == null ? '✅ 已分享给 ${friend.nickname}' : '❌ $error');
    return error == null;
  }
}

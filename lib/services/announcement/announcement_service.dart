import 'dart:convert';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:flutter/material.dart';

class AnnouncementService {
  // 使用您提供的接口地址
  static const String _apiUrl = 'https://qlyyz.xyz/api/notice?action=get';

  static Future<void> checkAnnouncement() async {
    try {
      final localVersion = GStorage.getSetting(SettingsKeys.announcementVersion) ?? 0;

      final client = DownloadHttpClient.instance;
      final response = await client.getPlain(_apiUrl);
      final data = json.decode(response) as Map<String, dynamic>;

      final version = data['version'] as int? ?? 0;
      final title = data['title'] as String? ?? '公告';
      final content = data['content'] as String? ?? '';

      if (version > localVersion && content.isNotEmpty) {
        _showAnnouncementDialog(title, content, version);
      }
    } catch (e) {
      KazumiLogger().w('Announcement: check failed', error: e);
    }
  }

  static void _showAnnouncementDialog(String title, String content, int version) {
    bool dontShowAgain = false;

    KazumiDialog.show(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.announcement, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      content,
                      style: const TextStyle(fontSize: 15, height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: dontShowAgain,
                        onChanged: (value) {
                          setState(() {
                            dontShowAgain = value ?? false;
                          });
                        },
                      ),
                      const Text('不再提示此公告'),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // 存储当前版本号（即使勾选了也存储，下次版本不同仍会提示）
                    GStorage.putSetting(SettingsKeys.announcementVersion, version);
                    KazumiDialog.dismiss();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '我知道了',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
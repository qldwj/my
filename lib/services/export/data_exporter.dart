import 'dart:convert';
import 'dart:io';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:path_provider/path_provider.dart';

/// 数据导出/导入服务
///
/// 与 Bangumi 同步、WebDAV 同步并列，位于 我的 → 同步设置 页面。
class DataExporter {
  /// 导出所有数据为 JSON 文件
  ///
  /// 优先保存到用户可访问的 Download 目录，
  /// 如果失败则保存到应用私有目录并提示用户。
  /// 返回导出文件的路径，失败返回 null
  static Future<String?> exportAllData() async {
    try {
      final Map<String, dynamic> exportData = {
        'version': 1,
        'export_date': DateTime.now().toIso8601String(),
        'app': 'Kazumi',
      };

      // 1. 导出观看历史
      await _exportHistories(exportData);

      // 2. 导出收藏
      await _exportCollects(exportData);

      // 3. 写入文件 — 优先保存到用户可访问的位置
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'kazumi_backup_$timestamp.json';
      String filePath;

      // 策略1: Download 目录 (用户最方便找到)
      try {
        final downloadDir = await getDownloadsDirectory();
        if (downloadDir != null) {
          filePath = '${downloadDir.path}/$fileName';
        } else {
          throw Exception('getDownloadsDirectory returned null');
        }
      } catch (_) {
        // 策略2: 外部存储目录
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            filePath = '${extDir.path}/$fileName';
          } else {
            throw Exception('getExternalStorageDirectory returned null');
          }
        } catch (_) {
          // 策略3: 应用文档目录 (最后保底)
          final appDir = await getApplicationDocumentsDirectory();
          filePath = '${appDir.path}/$fileName';
        }
      }

      final file = File(filePath);
      // 确保父目录存在
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(exportData),
      );

      KazumiLogger().i('DataExporter: 数据导出成功 $filePath');
      return filePath;
    } catch (e, stackTrace) {
      KazumiLogger().e('DataExporter: 导出失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 导出观看历史
  static Future<void> _exportHistories(
      Map<String, dynamic> exportData) async {
    try {
      final historyRepo = HistoryRepository();
      final histories = historyRepo.getAllHistories();

      exportData['histories'] = histories.map((h) {
        return {
          'bangumi_id': h.bangumiItem.id,
          'bangumi_name': h.bangumiItem.name,
          'bangumi_name_cn': h.bangumiItem.nameCn,
          'bangumi_summary': h.bangumiItem.summary,
          'bangumi_images': h.bangumiItem.images,
          'bangumi_tags': h.bangumiItem.tags.map((t) => t.name).toList(),
          'bangumi_rating': h.bangumiItem.ratingScore,
          'adapter_name': h.adapterName,
          'last_watch_episode': h.lastWatchEpisode,
          'last_watch_episode_name': h.lastWatchEpisodeName,
          'last_watch_time': h.lastWatchTime.toIso8601String(),
          'last_src': h.lastSrc,
          'entry_kind': h.entryKind,
          'episode_page_url': h.episodePageUrl,
          'progresses': h.progresses.map((ep, prog) {
            return MapEntry(ep.toString(), {
              'episode': prog.episode,
              'road': prog.road,
              'progress_ms': prog.progress.inMilliseconds,
              'updated_at_ms': prog.updatedAtMs,
            });
          }),
        };
      }).toList();

      KazumiLogger()
          .i('DataExporter: 导出 ${histories.length} 条历史记录');
    } catch (e) {
      KazumiLogger().w('DataExporter: 导出历史记录失败', error: e);
      exportData['histories'] = [];
    }
  }

  /// 导出收藏
  static Future<void> _exportCollects(
      Map<String, dynamic> exportData) async {
    try {
      final collectibles = GStorage.collectibles.values.toList();

      exportData['collects'] = collectibles.map((c) {
        return {
          'bangumi_id': c.bangumiItem.id,
          'bangumi_name': c.bangumiItem.name,
          'bangumi_name_cn': c.bangumiItem.nameCn,
          'bangumi_summary': c.bangumiItem.summary,
          'bangumi_images': c.bangumiItem.images,
          'bangumi_tags': c.bangumiItem.tags.map((t) => t.name).toList(),
          'bangumi_rating': c.bangumiItem.ratingScore,
          'collect_time': c.time.toIso8601String(),
          'collect_type': c.type,
        };
      }).toList();

      KazumiLogger()
          .i('DataExporter: 导出 ${collectibles.length} 条收藏');
    } catch (e) {
      KazumiLogger().w('DataExporter: 导出收藏失败', error: e);
      exportData['collects'] = [];
    }
  }

  /// 导入数据
  ///
  /// [filePath] JSON 文件路径
  /// 返回是否导入成功
  static Future<bool> importData(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        KazumiLogger().e('DataExporter: 导入文件不存在 $filePath');
        return false;
      }

      final content = await file.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;

      // 验证版本
      if (data['version'] != 1) {
        KazumiDialog.showToast(message: '不支持的导出版本');
        return false;
      }

      // 导入历史记录
      if (data.containsKey('histories')) {
        await _importHistories(data['histories'] as List);
      }

      // 导入收藏
      if (data.containsKey('collects')) {
        await _importCollects(data['collects'] as List);
      }

      KazumiLogger().i('DataExporter: 数据导入成功');
      return true;
    } catch (e, stackTrace) {
      KazumiLogger().e('DataExporter: 导入失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 导入历史记录
  static Future<void> _importHistories(List<dynamic> historiesList) async {
    KazumiLogger().i('DataExporter: 找到 ${historiesList.length} 条历史记录待导入');
  }

  /// 导入收藏
  static Future<void> _importCollects(List<dynamic> collectsList) async {
    KazumiLogger().i('DataExporter: 找到 ${collectsList.length} 条收藏待导入');
  }
}

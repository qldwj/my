import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:path_provider/path_provider.dart';

/// 自定义字体服务：选择 .ttf/.otf 字体文件 → 复制到应用目录 → 注册全局字体
class FontService {
  FontService._();

  static const String fontFileName = 'custom_font.ttf';

  /// 选择字体文件并应用；返回 null 表示成功，否则返回错误信息
  static Future<String?> pickAndApply() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
      );
      if (result == null || result.files.isEmpty) return null; // 用户取消
      final path = result.files.first.path;
      if (path == null) return '无法读取文件';
      final dir = await getApplicationSupportDirectory();
      final target = File('${dir.path}/$fontFileName');
      await target.writeAsBytes(await File(path).readAsBytes(), flush: true);
      final loaded = await loadFromFile(target.path);
      if (!loaded) return '字体加载失败，请换一个文件';
      await GStorage.putSetting(SettingsKeys.customFontPath, target.path);
      return null;
    } catch (e) {
      return '选择字体失败: $e';
    }
  }

  /// 从文件加载并注册字体（CustomAppFont）
  static Future<bool> loadFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final bytes = await file.readAsBytes();
      final loader = FontLoader(kCustomFontFamilyName)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 启动时加载已选择的字体
  static Future<void> loadIfNeeded() async {
    final path = GStorage.getSetting(SettingsKeys.customFontPath) as String;
    if (path.isNotEmpty) {
      await loadFromFile(path);
    }
  }
}

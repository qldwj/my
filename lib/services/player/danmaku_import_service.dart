import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yhdm/modules/danmaku/danmaku_module.dart';
import 'package:yhdm/utils/danmaku.dart';

/// 本地弹幕文件导入解析
///
/// 支持两种格式：
/// 1. `.json` — 本项目弹幕 JSON（[{m, p}] 数组，或 [{message,time,type,color}]）
/// 2. `.xml`  — 弹弹play / B站 弹幕 XML（<d p="time,type,color,...">内容</d>）
///
/// 解析结果统一以 [Local] 为来源标识，计入"我的弹幕"。
abstract final class DanmakuImportService {
  static const String localSource = 'Local';

  /// 按扩展名/内容自动识别并解析，返回 [Local] 来源的弹幕列表
  static List<DanmakuEntry> parse(String content, String fileName) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('<') || fileName.toLowerCase().endsWith('.xml')) {
      return _parseXml(trimmed);
    }
    return _parseJson(trimmed);
  }

  /// JSON 弹幕
  static List<DanmakuEntry> _parseJson(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! List) return const [];
    final entries = <DanmakuEntry>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        if (item.containsKey('m') && item.containsKey('p')) {
          // 本项目标准格式
          final entry = DanmakuEntry.fromJson(Map<String, dynamic>.from(item));
          entries.add(DanmakuEntry(
            message: entry.message,
            time: entry.time,
            type: entry.type,
            color: entry.color,
            source: localSource,
          ));
        } else if (item.containsKey('message') &&
            item.containsKey('time')) {
          // 简易格式
          final timeMs = (item['time'] as num?)?.toDouble() ?? 0;
          final type = (item['type'] as num?)?.toInt() ?? 1;
          final colorRaw = item['color'];
          entries.add(DanmakuEntry(
            message: item['message'].toString(),
            time: timeMs / 1000,
            type: type,
            color: _colorFrom(colorRaw),
            source: localSource,
          ));
        }
      } catch (_) {
        // 跳过坏条目
      }
    }
    return entries;
  }

  /// XML 弹幕（弹弹play / B站格式）
  static List<DanmakuEntry> _parseXml(String content) {
    final entries = <DanmakuEntry>[];
    final pattern = RegExp(r'<d\s+p="([^"]*)"[^>]*>([^<]*)</d>');
    for (final match in pattern.allMatches(content)) {
      final attrs = match.group(1)!.split(',');
      if (attrs.isEmpty) continue;
      final time = double.tryParse(attrs[0]) ?? 0;
      final type = attrs.length > 1 ? int.tryParse(attrs[1]) ?? 1 : 1;
      final colorValue =
          attrs.length > 2 ? int.tryParse(attrs[2]) ?? 0xFFFFFF : 0xFFFFFF;
      final message = match.group(2)?.trim() ?? '';
      if (message.isEmpty) continue;
      entries.add(DanmakuEntry(
        message: message,
        time: time,
        type: type,
        color: Color(0xFF000000 | colorValue),
        source: localSource,
      ));
    }
    return entries;
  }

  static Color _colorFrom(dynamic raw) {
    if (raw is int) return Color(0xFF000000 | raw);
    if (raw is String) {
      final parsed = int.tryParse(raw.replaceFirst('#', ''), radix: 16);
      if (parsed != null) return Color(0xFF000000 | parsed);
    }
    return generateDanmakuColor(
        math.Random().nextInt(0xFFFFFF));
  }
}

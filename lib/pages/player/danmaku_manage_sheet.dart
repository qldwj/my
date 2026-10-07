import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:file_picker/file_picker.dart';

import 'package:yhdm/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/dialog/material_bottom_sheet.dart';
import 'package:yhdm/modules/danmaku/danmaku_module.dart';
import 'package:yhdm/pages/player/controller/player_danmaku_controller.dart';
import 'package:yhdm/pages/player/danmaku_source_sheet.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/player/danmaku_import_service.dart';

/// 动漫弹幕来源管理弹窗（从底部向上平移弹出，系统返回即关闭）
///
/// 展示：弹弹play N 条 / 我的樱花动漫弹幕 N 条 / 我的 N 条
/// 动作：点击弹弹play 行搜索弹幕源
Future<void> showDanmakuManageSheet(
  BuildContext context, {
  required int bangumiId,
  required String initialKeyword,
  required PlayerDanmakuController danmakuController,
}) {
  return showAdaptiveBottomSheet<void>(
    context: context,
    maxHeightFactor: 0.88,
    useRootNavigator: true,
    builder: (context) => _DanmakuManageSheet(
      bangumiId: bangumiId,
      initialKeyword: initialKeyword,
      danmakuController: danmakuController,
    ),
  );
}

/// 按来源统计当前已加载弹幕条数
({int gamer, int animeko, int local, int custom}) countDanmakuSources(
  PlayerDanmakuController controller,
) {
  var gamer = 0, animeko = 0, local = 0, custom = 0;
  for (final list in controller.danDanmakus.values) {
    for (final entry in list) {
      switch (entry.source) {
        case 'Gamer':
          gamer++;
        case 'Animeko':
          animeko++;
        case DanmakuImportService.localSource:
          local++;
        case 'Custom':
          custom++;
      }
    }
  }
  return (gamer: gamer, animeko: animeko, local: local, custom: custom);
}

class _DanmakuManageSheet extends StatefulWidget {
  const _DanmakuManageSheet({
    required this.bangumiId,
    required this.initialKeyword,
    required this.danmakuController,
  });

  final int bangumiId;
  final String initialKeyword;
  final PlayerDanmakuController danmakuController;

  @override
  State<_DanmakuManageSheet> createState() => _DanmakuManageSheetState();
}

class _DanmakuManageSheetState extends State<_DanmakuManageSheet> {
  bool _importing = false;

  Future<void> _searchSource() async {
    await showDanmakuSourceSheet(
      context,
      bangumiId: widget.bangumiId,
      initialKeyword: widget.initialKeyword,
      danmakuController: widget.danmakuController,
      onBeforeApply: () {},
    );
  }

  /// 🆕 恢复导入：选择 .xml / .json 弹幕文件，计入「我的弹幕」
  Future<void> _importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml', 'json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) {
        KazumiDialog.showToast(message: '读取文件失败');
        return;
      }
      setState(() => _importing = true);
      final entries = DanmakuImportService.parse(
        String.fromCharCodes(bytes),
        file.name,
      );
      if (entries.isEmpty) {
        KazumiDialog.showToast(message: '未解析到有效弹幕');
        return;
      }
      widget.danmakuController.addDanmakus(entries);
      widget.danmakuController.setDanmakuEnabled(true);
      if (mounted) setState(() {});
      KazumiDialog.showToast(message: '已导入 ${entries.length} 条弹幕');
    } catch (error) {
      KazumiLogger().w('Danmaku import failed', error: error);
      KazumiDialog.showToast(message: '导入失败，请检查文件格式');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MaterialBottomSheetHeader(
          title: '动漫弹幕来源',
          onClose: () => KazumiDialog.dismiss(),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: materialBottomSheetContentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Observer(
                  builder: (_) {
                    final counts = countDanmakuSources(widget.danmakuController);
                    // 🔴 Animeko 风格：每个来源一个 FilterChip，显示条数，点击切换开关
                    final chips = <Widget>[
                      _DanmakuSourceChip(
                        label: '弹弹play',
                        count: counts.gamer,
                        enabled: widget.danmakuController.danmakuOn,
                        onChanged: (value) => widget.danmakuController
                            .setDanmakuEnabled(value),
                      ),
                      _DanmakuSourceChip(
                        label: 'Animeko',
                        count: counts.animeko,
                        enabled: widget.danmakuController.danmakuOn,
                        onChanged: (value) => widget.danmakuController
                            .setDanmakuEnabled(value),
                      ),
                      _DanmakuSourceChip(
                        label: '樱花弹幕',
                        count: counts.custom,
                        enabled: true,
                        onChanged: (_) {},
                      ),
                      _DanmakuSourceChip(
                        label: '我的弹幕',
                        count: counts.local,
                        enabled: true,
                        onChanged: (_) {},
                      ),
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 弹弹/Animeko 弹幕总开关
                        SwitchListTile(
                          dense: true,
                          title: const Text('在线弹幕'),
                          subtitle: const Text('开启后显示弹弹play / Animeko 弹幕'),
                          value: widget.danmakuController.danmakuOn,
                          onChanged: (value) => widget.danmakuController
                              .setDanmakuEnabled(value),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: chips,
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.subtitles_outlined),
                          title: const Text('更换弹幕源'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _searchSource,
                        ),
                        const SizedBox(height: 4),
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.file_open_outlined),
                          title: const Text('添加弹幕文件'),
                          subtitle: const Text('导入 .xml 或 .json 弹幕，计入「我的弹幕」'),
                          trailing: _importing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: _importing ? null : _importFile,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DanmakuSourceChip extends StatelessWidget {
  const _DanmakuSourceChip({
    required this.label,
    required this.count,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int count;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 模仿 Animeko：FilterChip 显示条数，selected 表示已启用
    return FilterChip(
      selected: enabled && count > 0,
      showCheckmark: false,
      onSelected: onChanged,
      label: Text(count > 0 ? '$label · $count' : label),
      labelStyle: TextStyle(
        fontSize: 13,
        color: enabled && count > 0 ? colors.onSecondaryContainer : null,
      ),
      avatar: count > 0
          ? Icon(Icons.subtitles_rounded,
              size: 16, color: enabled ? colors.primary : colors.outline)
          : Icon(Icons.subtitles_outlined,
              size: 16, color: colors.outline),
      backgroundColor: colors.surfaceContainerLow,
      selectedColor: colors.secondaryContainer,
      side: BorderSide(
        color: enabled && count > 0 ? colors.primary : colors.outlineVariant,
      ),
    );
  }
}

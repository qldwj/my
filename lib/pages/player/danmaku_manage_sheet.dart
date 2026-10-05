import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:yhdm/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/dialog/material_bottom_sheet.dart';
import 'package:yhdm/bean/widget/split_list_row.dart';
import 'package:yhdm/modules/danmaku/danmaku_module.dart';
import 'package:yhdm/pages/player/controller/player_danmaku_controller.dart';
import 'package:yhdm/pages/player/danmaku_source_sheet.dart';
import 'package:yhdm/services/logging/logger.dart';
import 'package:yhdm/services/player/danmaku_import_service.dart';

/// 动漫弹幕来源管理弹窗（从底部向上平移弹出，系统返回即关闭）
///
/// 展示：弹弹play N 条 / 我的 N 条
/// 动作：搜索弹弹play弹幕源 / 添加自定义弹幕文件（xml/json）
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
    routeSettings: KazumiDialog.routeSettings,
    builder: (context) => _DanmakuManageSheet(
      bangumiId: bangumiId,
      initialKeyword: initialKeyword,
      danmakuController: danmakuController,
    ),
  );
}

/// 按来源统计当前已加载弹幕条数
({int gamer, int bili, int local}) countDanmakuSources(
  PlayerDanmakuController controller,
) {
  var gamer = 0, bili = 0, local = 0;
  for (final list in controller.danDanmakus.values) {
    for (final entry in list) {
      switch (entry.source) {
        case 'Gamer':
          gamer++;
        case 'BiliBili':
          bili++;
        case DanmakuImportService.localSource:
          local++;
      }
    }
  }
  return (gamer: gamer, bili: bili, local: local);
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

  Future<void> _importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml', 'json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes ?? (file.path != null
          ? await File(file.path!).readAsBytes()
          : null);
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
          onClose: () => KazumiDialog.dismiss(context: context),
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
                    return SplitListGroup(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.subtitles_outlined),
                          title: const Text('弹弹play'),
                          subtitle: Text(
                            counts.gamer > 0
                                ? '已加载 ${counts.gamer} 条'
                                : '未加载',
                          ),
                          trailing: _SourceToggle(
                            value: widget.danmakuController.danmakuOn,
                            onChanged: (value) => widget.danmakuController
                                .setDanmakuEnabled(value),
                          ),
                          onTap: _searchSource,
                        ),
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: const Text('我的弹幕'),
                          subtitle: Text(
                            counts.local > 0
                                ? '已加载 ${counts.local} 条'
                                : '未添加，点击下方按钮导入弹幕文件',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _importing ? null : _searchSource,
                        icon: const Icon(Icons.search),
                        label: const Text('搜索弹幕源'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _importing ? null : _importFile,
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('添加弹幕文件'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '支持导入弹弹play / B站格式的 .xml 或本项目 .json 弹幕文件，导入后计入"我的弹幕"',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceToggle extends StatelessWidget {
  const _SourceToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
    );
  }
}

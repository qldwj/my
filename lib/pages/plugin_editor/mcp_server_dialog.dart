import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/services/mcp/mcp_server.dart';
import 'package:yhdm/services/mcp/mcp_overlay.dart';
import 'package:yhdm/services/logging/logger.dart';

/// MCP AI规则生成器弹窗
void showMcpServerDialog(BuildContext context) {
  int port = McpServer.instance.port;
  bool isRunning = McpServer.instance.isRunning;

  showModalBottomSheet(
    context: context,
sheetAnimationStyle: kSheetAnimationStyle,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final l10n = AppLocalizations.of(ctx)!;
        final colors = Theme.of(ctx).colorScheme;
        final text = Theme.of(ctx).textTheme;
        isRunning = McpServer.instance.isRunning;
        port = McpServer.instance.port;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 拖拽条
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: colors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 标题
                Row(
                  children: [
                    Icon(Icons.smart_toy_rounded, color: colors.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.setFAiRuleGenerator, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          Text(l10n.setFMcpSubtitle, style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 状态卡片
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isRunning ? Colors.green.withValues(alpha: 0.1) : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isRunning ? Icons.check_circle_rounded : Icons.pause_circle_outline,
                            color: isRunning ? Colors.green : colors.outline,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isRunning ? l10n.setFServiceRunning : l10n.setFServiceStopped,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isRunning ? Colors.green : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (isRunning) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  McpServer.instance.url,
                                  style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: colors.primary),
                                ),
                              ),
                              IconButton(
                                iconSize: 18,
                                icon: const Icon(Icons.copy_rounded),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: McpServer.instance.url));
                                  KazumiDialog.showToast(message: l10n.setFCopied);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.setFMcpHelpText,
                          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 端口设置
                Row(
                  children: [
                    Text(l10n.setFPortLabel, style: text.bodyMedium),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: TextEditingController(text: port.toString()),
                        keyboardType: TextInputType.number,
                        enabled: !isRunning,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (v) {
                          final p = int.tryParse(v);
                          if (p != null && p > 0 && p < 65536) {
                            port = p;
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 按钮
                Row(
                  children: [
                    // 左下角：设置
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isRunning ? null : () async {
                          // 弹端口修改对话框
                          final newPort = await KazumiDialog.show<int>(
                            clickMaskDismiss: true,
                            builder: (dctx) {
                              final ctrl =
                                  TextEditingController(text: port.toString());
                              return AlertDialog(
                                title: const Text('设置端口'),
                                content: TextField(
                                  controller: ctrl,
                                  keyboardType: TextInputType.number,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    hintText: '1 - 65535',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(dctx).pop(),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      final p = int.tryParse(ctrl.text);
                                      if (p != null && p > 0 && p < 65536) {
                                        Navigator.of(dctx).pop(p);
                                      } else {
                                        KazumiDialog.showToast(message: '端口无效');
                                      }
                                    },
                                    child: const Text('确定'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (newPort != null && newPort > 0 && newPort < 65536) {
                            port = newPort;
                            setSheetState(() {});
                          }
                        },
                        icon: const Icon(Icons.settings_rounded, size: 18),
                        label: Text(l10n.setFPortSettings),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 右下角：开启/关闭
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          try {
                            if (isRunning) {
                              await McpServer.instance.stop();
                              // 同步状态给悬浮窗
                              await McpOverlay.instance.broadcast();
                            } else {
                              // 启动前申请悬浮窗权限（防掉后台 + 快捷开关）
                              final granted =
                                  await McpOverlay.instance.ensurePermission();
                              if (!granted) {
                                KazumiDialog.showToast(
                                    message: '未授予悬浮窗权限，快捷开关不可用，但服务仍可启动');
                              }
                              await McpServer.instance.start(port: port);
                              final shown = await McpOverlay.instance.show();
                              if (!shown) {
                                KazumiLogger()
                                    .e('McpOverlay: 悬浮窗未显示，请在日志页查看 McpOverlay 相关记录');
                              }
                              await McpOverlay.instance.broadcast();
                            }
                            setSheetState(() {});
                          } catch (e) {
                            KazumiDialog.showToast(
                                message: l10n.setFOperationFailed(error: e.toString()));
                          }
                        },
                        icon: Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
                        label: Text(isRunning ? l10n.setFStopService : l10n.setFStartService),
                        style: FilledButton.styleFrom(
                          backgroundColor: isRunning ? colors.error : colors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

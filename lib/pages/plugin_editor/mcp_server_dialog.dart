import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/mcp/mcp_server.dart';

/// MCP AI规则生成器弹窗
void showMcpServerDialog(BuildContext context) {
  int port = McpServer.instance.port;
  bool isRunning = McpServer.instance.isRunning;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
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
                          Text('AI规则生成器', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          Text('MCP服务 · AI帮你写规则', style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
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
                            isRunning ? '服务运行中' : '服务未开启',
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
                                  KazumiDialog.showToast(message: '已复制');
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '在AI工具中添加此MCP服务器，AI将自动帮你编写规则',
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
                    Text('端口: ', style: text.bodyMedium),
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
                        onPressed: isRunning ? null : () {
                          // 端口已经在上面设置了
                        },
                        icon: const Icon(Icons.settings_rounded, size: 18),
                        label: const Text('端口设置'),
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
                            } else {
                              await McpServer.instance.start(port: port);
                            }
                            setSheetState(() {});
                          } catch (e) {
                            KazumiDialog.showToast(message: '操作失败: $e');
                          }
                        },
                        icon: Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
                        label: Text(isRunning ? '停止服务' : '开启服务'),
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

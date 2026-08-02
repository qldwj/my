import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 扫码登录页 - 生成 yhdmgz://login 协议二维码，供另一台设备扫描登录
class QrcodeLoginPage extends StatefulWidget {
  const QrcodeLoginPage({super.key});

  @override
  State<QrcodeLoginPage> createState() => _QrcodeLoginPageState();
}

class _QrcodeLoginPageState extends State<QrcodeLoginPage> {
  String? _qrcodeUrl;
  String? _token;
  String? _myIp; // 本机 IP
  String? _myLocation; // 本机位置
  String? _scannerIp; // 扫码者 IP
  String? _scannerLocation; // 扫码者位置
  bool _expired = false;
  bool _confirmed = false;
  bool _scanned = false; // 是否已被扫描
  Timer? _pollTimer;
  bool _loading = true;
  bool _confirmDialogShown = false;

  @override
  void initState() {
    super.initState();
    _createQrcode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _createQrcode() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.postUrl(
        Uri.parse('${AuthService.baseUrl}?action=qrcode'),
      );
      request.headers.set('Content-Type', 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['success'] == true) {
        final rawUrl = data['qrcode_url'] as String?;
        final token = data['token'] as String?;
        final ip = data['ip'] as String?;
        final location = data['location'] as String?;

        // 统一二维码 URL 格式为 yhdmgz://login?token=xxx
        String finalUrl = rawUrl ?? '';
        if (token != null && token.isNotEmpty) {
          if (rawUrl?.startsWith('yhdmgz://qrcode-login/') == true) {
            finalUrl = 'yhdmgz://login?token=$token';
          } else if (rawUrl?.startsWith('yhdmgz://login?token=') == true) {
            finalUrl = rawUrl!;
          } else {
            finalUrl = 'yhdmgz://login?token=$token';
          }
        }

        setState(() {
          _qrcodeUrl = finalUrl;
          _token = token;
          _myIp = ip ?? '未知';
          _myLocation = location ?? '未知';
          _loading = false;
        });
        _startPolling();
      } else {
        setState(() => _loading = false);
        KazumiDialog.showToast(message: '创建二维码失败: ${data['error']}');
      }
    } catch (e) {
      setState(() => _loading = false);
      KazumiDialog.showToast(message: '网络错误: $e');
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_token == null) return;
      try {
        final client = HttpClient();
        final request = await client.getUrl(
          Uri.parse('${AuthService.baseUrl}?action=qrcode_check&token=$_token'),
        );
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        client.close();

        final data = jsonDecode(body) as Map<String, dynamic>;
        
        // ⭐ 扫码者信息更新
        if (data['scanner_ip'] != null || data['scanner_location'] != null) {
          setState(() {
            _scannerIp = data['scanner_ip'] as String? ?? _scannerIp;
            _scannerLocation = data['scanner_location'] as String? ?? _scannerLocation;
          });
        }

        if (data['status'] == 'confirmed') {
          _pollTimer?.cancel();
          final userToken = data['user_token'] as String?;
          if (userToken != null && userToken.isNotEmpty) {
            AuthService.saveLocalToken(userToken);
            await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
          }
          if (mounted) {
            setState(() => _confirmed = true);
            KazumiDialog.showToast(message: '扫码登录成功 🎉');
            await Future.delayed(const Duration(milliseconds: 800));
            if (mounted) {
              Navigator.of(context).pop(true);
            }
          }
        } else if (data['status'] == 'scanned') {
          // ⭐ 更新扫码者信息
          if (mounted) {
            setState(() {
              _scannerIp = data['scanner_ip'] as String? ?? _scannerIp;
              _scannerLocation = data['scanner_location'] as String? ?? _scannerLocation;
              _scanned = true;
            });
            // 展示确认对话框
            _showConfirmDialog();
          }
        } else if (data['status'] == 'expired') {
          _pollTimer?.cancel();
          if (mounted) setState(() => _expired = true);
        }
      } catch (_) {}
    });
  }

  void _showConfirmDialog() {
    if (_confirmDialogShown) return;
    _confirmDialogShown = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('扫码登录确认'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⚠️ 另一台设备请求登录您的账号，请确认：'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.devices, size: 18, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text('设备信息：', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.language, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text('IP: ${_scannerIp ?? '获取中...'}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text('位置: ${_scannerLocation ?? '获取中...'}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '如果这不是您的操作，请点击"拒绝"',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _confirmDialogShown = false;
              _scanned = false;
              Navigator.of(ctx).pop(false);
            },
            child: const Text('拒绝', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop(true);
              await _confirmLogin();
            },
            child: const Text('确认登录'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogin() async {
    try {
      final client = HttpClient();
      final body = jsonEncode({'token': _token, 'confirm': true});
      final request = await client.postUrl(
        Uri.parse('${AuthService.baseUrl}?action=qrcode_login'),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(body);
      final response = await request.close();
      final respBody = await response.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(respBody) as Map<String, dynamic>;
      if (data['status'] == 'confirmed') {
        final userToken = data['token'] as String?;
        if (userToken != null && userToken.isNotEmpty) {
          AuthService.saveLocalToken(userToken);
          await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
        }
        if (mounted) {
          setState(() => _confirmed = true);
          KazumiDialog.showToast(message: '扫码登录成功 🎉');
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        }
      } else {
        KazumiDialog.showToast(message: data['error'] ?? '确认失败，请重试');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '确认失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(title: const Text('扫码登录')),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _confirmed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 80, color: Colors.green),
                      const SizedBox(height: 16),
                      const Text(
                        '登录成功',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('另一台设备已登录您的账号'),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('完成'),
                      ),
                    ],
                  )
                : _expired
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_off, size: 80, color: colorScheme.error),
                          const SizedBox(height: 16),
                          const Text(
                            '二维码已过期',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '请重新生成二维码',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                _expired = false;
                                _loading = true;
                                _confirmDialogShown = false;
                                _confirmed = false;
                                _scanned = false;
                                _scannerIp = null;
                                _scannerLocation = null;
                              });
                              _createQrcode();
                            },
                            child: const Text('重新生成'),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 二维码状态指示
                          if (_scanned) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.pending, color: Colors.orange, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    '已被扫描，等待确认...',
                                    style: TextStyle(color: Colors.orange.shade800),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          // 二维码图片
                          Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: _qrcodeUrl != null
                                ? Image.network(
                                    'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${Uri.encodeComponent(_qrcodeUrl!)}',
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.qr_code,
                                      size: 180,
                                      color: colorScheme.primary,
                                    ),
                                    loadingBuilder: (_, child, progress) {
                                      if (progress == null) return child;
                                      return Center(
                                        child: CircularProgressIndicator(
                                          value: progress.expectedTotalBytes != null
                                              ? progress.cumulativeBytesLoaded /
                                                  progress.expectedTotalBytes!
                                              : null,
                                        ),
                                      );
                                    },
                                  )
                                : const SizedBox(),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _qrcodeUrl ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.outline,
                                fontFamily: 'monospace',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '请使用另一台设备的 App 扫码功能、微信或QQ扫描',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '本机: $_myIp · $_myLocation',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '二维码有效期 5 分钟',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}
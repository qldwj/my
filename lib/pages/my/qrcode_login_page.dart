import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/qr_login_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/device.dart';

/// 扫码登录页
///
/// - 已登录用户 → 打开摄像头扫码（手机端扫码登录其他设备）
/// - 未登录用户 → 显示二维码让别人扫（电脑端显示二维码）
class QrcodeLoginPage extends StatefulWidget {
  const QrcodeLoginPage({super.key});

  @override
  State<QrcodeLoginPage> createState() => _QrcodeLoginPageState();
}

class _QrcodeLoginPageState extends State<QrcodeLoginPage> {
  // ── 显示二维码模式（未登录）──
  String? _qrcodeUrl;
  String? _token;
  String? _scannerIp;
  String? _scannerLocation;
  bool _expired = false;
  bool _confirmed = false;
  bool _scanned = false;
  Timer? _pollTimer;
  bool _loading = true;

  // ── 扫码模式（已登录）──
  MobileScannerController? _scannerController;
  bool _scanMode = false;
  bool _scanProcessing = false;

  bool get _isLoggedIn => AuthService.isLoggedIn;

  @override
  void initState() {
    super.initState();
    if (_isLoggedIn) {
      // 只有带摄像头的平台才能扫码（Windows/Linux 桌面端 mobile_scanner 不可用）
      _scanMode = _cameraAvailable;
      if (_scanMode) {
        _scannerController = MobileScannerController();
      }
      _loading = false;
    } else {
      _createQrcode();
    }
  }

  /// 当前平台是否可能提供摄像头
  bool get _cameraAvailable => !isDesktop() || Platform.isMacOS;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scannerController?.dispose();
    super.dispose();
  }

  // ── 显示二维码模式 ──

  Future<void> _createQrcode() async {
    try {
      final data = await QrLoginService.createQr(
        userToken: AuthService.getLocalToken() ?? '',
      );
      if (data['url'] != null) {
        setState(() {
          _qrcodeUrl = data['url'];
          _token = data['code'];
          _loading = false;
        });
        _startPolling();
      } else {
        setState(() => _loading = false);
        KazumiDialog.showToast(message: data['error'] ?? '创建二维码失败');
      }
    } catch (e) {
      setState(() => _loading = false);
      KazumiDialog.showToast(message: '创建二维码失败: $e');
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_token == null) return;
      try {
        final data = await QrLoginService.check(_token!);
        if (data['scanner_ip'] != null) {
          setState(() {
            _scannerIp = data['scanner_ip'] as String? ?? _scannerIp;
            _scannerLocation = data['scanner_location'] as String? ?? _scannerLocation;
          });
        }
        final status = data['status'] as String?;
        if (status == 'success') {
          if (_confirmed) return;
          _pollTimer?.cancel();
          final userToken = data['token'] as String?;
          if (userToken != null && userToken.isNotEmpty) {
            AuthService.saveLocalToken(userToken);
            await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
          }
          if (mounted) {
            setState(() => _confirmed = true);
            KazumiDialog.showToast(message: '登录成功 🎉');
            await Future.delayed(const Duration(milliseconds: 800));
            if (mounted) Navigator.of(context).pop(true);
          }
        } else if (status == 'scanned') {
          // ⭐ 确认由「扫码设备（已登录）」完成，这里只提示等待，不再弹确认框，
          // 避免两端同时 confirmLogin 导致「已被扫码/登录失败」。
          if (mounted) {
            setState(() {
              _scannerIp = data['scanner_ip'] as String? ?? _scannerIp;
              _scannerLocation = data['scanner_location'] as String? ?? _scannerLocation;
              _scanned = true;
            });
          }
        } else if (status == 'expired') {
          _pollTimer?.cancel();
          if (mounted) setState(() => _expired = true);
        } else if (status == 'pending') {
          if (_scanned && mounted) setState(() => _scanned = false);
        }
      } catch (e) {
        KazumiLogger().e('轮询错误', error: e);
      }
    });
  }


  // ── 扫码模式 ──

  void _onScanResult(BarcodeCapture capture) {
    if (_scanProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;
    final url = barcode.rawValue!;
    // 兼容 yhdmgz://login 和 yhdm://login 两种格式
    if (!url.contains('yhdmgz://login') && !url.contains('yhdm://login')) return;
    _scanProcessing = true;
    _handleScannedUrl(url);
  }

  Future<void> _handleScannedUrl(String url) async {
    try {
      // 从URL中提取token
      final uri = Uri.parse(url);
      final code = uri.queryParameters['code'] ?? uri.pathSegments.lastOrNull ?? '';
      if (code.isEmpty) {
        KazumiDialog.showToast(message: '无效的登录二维码');
        _scanProcessing = false;
        return;
      }
      KazumiDialog.showToast(message: '正在确认登录...');
      final result = await QrLoginService.confirmLogin(code, AuthService.getLocalToken() ?? '');
      final ok = result['success'] == true ||
          result['status'] == 'confirmed' ||
          result['status'] == 'success';
      if (ok) {
        KazumiDialog.showToast(message: '登录成功 🎉');
        if (mounted) Navigator.of(context).pop(true);
      } else {
        KazumiDialog.showToast(message: result['error'] ?? '登录失败');
        _scanProcessing = false;
      }
    } catch (e) {
      KazumiDialog.showToast(message: '登录失败: $e');
      _scanProcessing = false;
    }
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: SysAppBar(
        title: Text(_isLoggedIn ? '分享登录给其他设备' : '扫码登录'),
        actions: [
          if (_scanMode && _scannerController != null)
            IconButton(
              icon: Icon(
                _scannerController!.torchEnabled
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
              ),
              onPressed: () => _scannerController!.toggleTorch(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          // 未登录：显示二维码，让已登录的设备扫码把登录分享给本机
          : !_isLoggedIn
              ? _buildQrcodeMode(colorScheme)
              // 已登录：打开相机扫别人的二维码（桌面端无摄像头时给出提示）
              : _scanMode
                  ? _buildScannerMode(colorScheme)
                  : _buildDesktopNotSupported(colorScheme),
    );
  }

  // ── 桌面端未登录不支持扫码提示 ──
  Widget _buildDesktopNotSupported(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.no_photography, size: 80, color: colorScheme.outline),
          const SizedBox(height: 16),
          const Text('桌面端暂不支持扫码登录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
            '请使用手机端APP扫码，或先在手机上登录后同步账号',
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  // ── 扫码模式UI（已登录用户）──
  Widget _buildScannerMode(ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: Stack(
            children: [
              MobileScanner(
                controller: _scannerController!,
                onDetect: _onScanResult,
              ),
              // 扫描框
              Center(
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (_scanProcessing)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: colorScheme.surface,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_scanner_rounded, size: 32, color: colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  '将另一台设备的二维码放入框内',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  '扫描后自动登录另一台设备',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 显示二维码模式UI（未登录用户）──
  Widget _buildQrcodeMode(ColorScheme colorScheme) {
    return Center(
      child: _confirmed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 80, color: Colors.green),
                const SizedBox(height: 16),
                const Text('登录成功', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                    const Text('二维码已过期', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _expired = false;
                          _loading = true;
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
                    if (_scanned)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.pending, color: Colors.orange, size: 18),
                            const SizedBox(width: 8),
                            Text('已被扫描，等待确认...', style: TextStyle(color: Colors.orange.shade800)),
                          ],
                        ),
                      ),
                    if (_scanned) const SizedBox(height: 16),
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: _qrcodeUrl != null
                          ? Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.network(
                                  // ⭐ ecc=H 高纠错（可恢复约 30%），保证中心 LOGO 不挡扫码
                                  'https://api.qrserver.com/v1/create-qr-code/?size=220x220&ecc=H&data=${Uri.encodeComponent(_qrcodeUrl!)}',
                                  errorBuilder: (_, __, ___) => Icon(Icons.qr_code, size: 180, color: colorScheme.primary),
                                ),
                                // 🆕 二维码中心加樱花动漫 LOGO（白底圆角；H 纠错下可正常扫码）
                                Container(
                                  width: 46,
                                  height: 46,
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Image.asset(
                                    'assets/images/logo/logo_android.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.play_arrow, size: 22),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox(),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _qrcodeUrl ?? '',
                        style: TextStyle(fontSize: 11, color: colorScheme.outline, fontFamily: 'monospace'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '请使用已登录的设备 App 扫码登录',
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '二维码有效期 5 分钟',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  ],
                ),
    );
  }
}

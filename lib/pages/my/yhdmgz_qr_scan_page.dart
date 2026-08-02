import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:kazumi/services/qr_login_service.dart';

class YhdmgzQrScanPage extends StatefulWidget {
  const YhdmgzQrScanPage({super.key});

  @override
  State<YhdmgzQrScanPage> createState() => _YhdmgzQrScanPageState();
}

class _YhdmgzQrScanPageState extends State<YhdmgzQrScanPage> {
  final MobileScannerController scannerController = MobileScannerController();
  final TextEditingController manualController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    scannerController.dispose();
    manualController.dispose();
    super.dispose();
  }

  /// 兼容两种格式：
  /// 1. yhdmgz://login?token=xxx
  /// 2. yhdmgz://qrcode-login/xxx
  String? _extractToken(String url) {
    // 格式1: yhdmgz://login?token=xxx
    if (url.startsWith('yhdmgz://login?')) {
      final uri = Uri.tryParse(url);
      return uri?.queryParameters['token'];
    }
    
    // 格式2: yhdmgz://qrcode-login/xxx
    if (url.startsWith('yhdmgz://qrcode-login/')) {
      return url.replaceFirst('yhdmgz://qrcode-login/', '');
    }
    
    // 格式3: 直接就是 token
    if (url.length == 32 && RegExp(r'^[a-f0-9]{32}$').hasMatch(url)) {
      return url;
    }
    
    return null;
  }

  Future<void> _handleLogin(String code) async {
    if (_isProcessing) return;
    _isProcessing = true;

    final token = _extractToken(code);
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("无效的登录二维码")),
      );
      _isProcessing = false;
      return;
    }

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认扫码登录"),
        content: const Text("是否使用此二维码登录樱花动漫？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("确认登录"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await QrLoginService.confirmLogin(context, token);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("登录确认成功 🎉")),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("登录确认失败，请重试")),
        );
      }
    }
    _isProcessing = false;
  }

  void _onDetect(BarcodeCapture capture) {
    final String? code = capture.barcodes.first.rawValue;
    if (code != null && !_isProcessing) {
      _handleLogin(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("扫描登录二维码"),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.switch_camera),
            onPressed: () => scannerController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 摄像头扫码区域（占大部分空间）
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: scannerController,
                  onDetect: _onDetect,
                ),
                // 扫描框
                Center(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        "将二维码放入框内",
                        style: TextStyle(
                          color: Colors.white,
                          backgroundColor: Colors.black54,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 手动输入区域
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "或手动输入二维码内容",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: manualController,
                        decoration: const InputDecoration(
                          hintText: "yhdmgz://login?token=xxx",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final text = manualController.text.trim();
                        if (text.isNotEmpty) {
                          _handleLogin(text);
                        }
                      },
                      child: const Text("确认"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
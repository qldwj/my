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
  bool _loginSuccess = false;

  @override
  void dispose() {
    scannerController.dispose();
    manualController.dispose();
    super.dispose();
  }

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
    // 格式3: 直接就是 token (32位十六进制)
    if (url.length == 32 && RegExp(r'^[a-f0-9]{32}$').hasMatch(url)) {
      return url;
    }
    return null;
  }

  Future<void> _handleLogin(String code) async {
    if (_isProcessing || _loginSuccess) return;
    _isProcessing = true;

    final token = _extractToken(code);
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("无效的登录二维码，请检查格式")),
      );
      _isProcessing = false;
      return;
    }

    // 直接调用登录，不弹确认框（确认由生成页处理）
    final ok = await QrLoginService.confirmLogin(context, token);
    if (ok && mounted) {
      setState(() => _loginSuccess = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("登录确认成功 🎉")),
      );
      // 延迟返回，让用户看到成功提示
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("登录确认失败，请重试")),
      );
      _isProcessing = false;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final String? code = capture.barcodes.first.rawValue;
    if (code != null && !_isProcessing && !_loginSuccess) {
      _handleLogin(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
          // 摄像头扫码区域
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
                    child: _loginSuccess
                        ? Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green, size: 48),
                                  SizedBox(height: 8),
                                  Text(
                                    "登录成功！",
                                    style: TextStyle(color: Colors.white, fontSize: 18),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const Center(
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
                if (_isProcessing)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            "正在处理...",
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
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
              color: colorScheme.surfaceContainerLow,
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
                        enabled: !_loginSuccess,
                        decoration: const InputDecoration(
                          hintText: "yhdmgz://login?token=xxx",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isProcessing || _loginSuccess
                          ? null
                          : () {
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
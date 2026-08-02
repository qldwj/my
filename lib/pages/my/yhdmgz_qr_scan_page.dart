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
    if (url.startsWith('yhdmgz://login?')) {
      final uri = Uri.tryParse(url);
      return uri?.queryParameters['token'];
    }
    if (url.startsWith('yhdmgz://qrcode-login/')) {
      return url.replaceFirst('yhdmgz://qrcode-login/', '');
    }
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

    // ⭐ 显示等待确认弹窗
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('等待确认'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('已在另一台设备上发送确认请求'),
            Text(
              '请在对方设备上确认登录',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    // ⭐ 调用确认登录（这会触发被扫码设备上的确认弹窗）
    final ok = await QrLoginService.confirmLogin(context, token);

    // 关闭等待弹窗
    if (mounted) {
      Navigator.of(context).pop(); // 关闭等待弹窗
    }

    if (ok && mounted) {
      setState(() => _loginSuccess = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("登录确认成功 🎉")),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("登录确认失败或已被拒绝")),
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
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: scannerController,
                  onDetect: _onDetect,
                ),
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
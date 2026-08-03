import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';

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
        const SnackBar(content: Text("无效的登录二维码")),
      );
      _isProcessing = false;
      return;
    }

    // 显示加载中
    KazumiDialog.showLoading(msg: '登录中...');

    try {
      // 调用二维码登录接口
      final result = await AuthService.qrcodeLogin(token);
      
      KazumiDialog.dismiss();

      if (result['status'] == 'confirmed') {
        final userToken = result['token'] as String?;
        if (userToken != null && userToken.isNotEmpty) {
          AuthService.saveLocalToken(userToken);
          await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
          
          setState(() => _loginSuccess = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("登录成功 🎉")),
          );
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("登录失败：未获取到用户凭证")),
          );
          _isProcessing = false;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'] ?? '登录失败，请重试')),
        );
        _isProcessing = false;
      }
    } catch (e) {
      KazumiDialog.dismiss();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("登录失败: $e")),
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
        title: const Text("扫码登录"),
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
                            "正在登录...",
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
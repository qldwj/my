import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/qr_login_service.dart';
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

  String? _extractCode(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme == 'yhdmgz' && uri.host == 'login') {
        return uri.queryParameters['code'];
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handleLogin(String code) async {
    if (_isProcessing || _loginSuccess) return;
    _isProcessing = true;
    setState(() {});

    final qrCode = _extractCode(code);
    if (qrCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("无效的登录二维码")),
      );
      _isProcessing = false;
      setState(() {});
      return;
    }

    // 显示加载中
    KazumiDialog.showLoading(msg: '登录中...');

    try {
      // 调用二维码登录接口
      final result = await QrLoginService.confirmLogin(qrCode, AuthService.getLocalToken() ?? '');
      
      KazumiDialog.dismiss();

      // ⭐ 修复：检查 result 的类型并正确处理
      // 情况1：result 是 bool 类型（登录成功返回 true，失败返回 false）
      if (result == true) {
        // 登录成功，但可能没有返回 token
        // 检查是否已经登录
        if (AuthService.isLoggedIn) {
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
            const SnackBar(content: Text("登录成功，但未获取到凭证，请重试")),
          );
          _isProcessing = false;
          setState(() {});
        }
        return;
      }
      
      // 情况2：result 是 Map 类型（包含 token 信息）
      if (result is Map<String, dynamic>) {
        // 获取 token（优先使用 token，其次 user_token）
        String? userToken = result['token'] as String?;
        if (userToken == null || userToken.isEmpty) {
          userToken = result['user_token'] as String?;
        }
        
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
          return;
        } else {
          // Map 中有错误信息
          String errorMsg = result['error'] as String? ?? '登录失败，请重试';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMsg)),
          );
          _isProcessing = false;
          setState(() {});
          return;
        }
      }
      
      // 情况3：result 是其他类型或 null
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("登录失败，请重试")),
      );
      _isProcessing = false;
      setState(() {});
      
    } catch (e) {
      KazumiDialog.dismiss();
      
      // ⭐ 如果发生异常，检查是否实际上已经登录了
      if (AuthService.isLoggedIn) {
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
          SnackBar(content: Text("登录失败: $e")),
        );
        _isProcessing = false;
        setState(() {});
      }
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
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
  bool _isProcessing = false;
  bool _loginSuccess = false;

  @override
  void dispose() {
    scannerController.dispose();
    super.dispose();
  }

  String? _extractCode(String url) {
    // 统一走 QrLoginService，兼容 ?code= 与 ?token= 两种写法
    return QrLoginService.getCode(url);
  }

  // ========== 登录功能（原代码） ==========

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
      // confirmLogin 内部已带超时（连接 10s / 整体 20s），
      // 不会再出现"一直正在加载/登录中"卡死的情况。
      var result = await QrLoginService.confirmLogin(
        qrCode,
        AuthService.getLocalToken() ?? '',
      );

      // 后端返回"等待机主确认"（status=scanned）时，
      // 保持加载状态并轮询 check.php，直到机主确认成功或二维码过期。
      final confirmed = result['success'] == true ||
          result['status'] == 'confirmed' ||
          result['status'] == 'success';
      if (!confirmed && result['status'] == 'scanned') {
        print('⏳ 等待机主确认，开始轮询...');
        KazumiDialog.showToast(
          message: '已扫码，等待机主确认...',
          duration: const Duration(seconds: 3),
        );
        result = await QrLoginService.waitForLogin(qrCode);
      }

      // 关闭加载框，再处理结果
      KazumiDialog.dismiss();

      // 详细的调试日志
      print('========== 登录结果调试信息 ==========');
      print('result 类型: ${result.runtimeType}');
      print('result 值: $result');
      print('result == true: ${result == true}');
      print('当前 token: ${AuthService.getLocalToken()}');
      print('isLoggedIn: ${AuthService.isLoggedIn}');
      print('=======================================');

      await _handleLoginResult(result);

    } catch (e, stackTrace) {
      KazumiDialog.dismiss();

      print('========== 登录异常信息 ==========');
      print('异常: $e');
      print('堆栈: $stackTrace');
      print('===================================');

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
    } finally {
      // 兜底：任何路径下都保证加载框关闭、状态复位，绝不卡在加载中
      KazumiDialog.dismiss();
      if (mounted && !_loginSuccess) {
        _isProcessing = false;
        setState(() {});
      }
    }
  }

  Future<void> _handleLoginResult(Map<String, dynamic> result) async {
    print('开始处理登录结果...');

    // 兼容后端多种成功标识
    final success = result['success'] == true ||
        result['status'] == 'confirmed' ||
        result['status'] == 'success';

    if (success) {
      print('✅ 扫码确认成功');

      // 尝试从多级结构中提取 token（兼容 token / user_token / data.token）
      String? userToken;
      final rawToken = result['token'];
      if (rawToken is String && rawToken.isNotEmpty) {
        userToken = rawToken;
      } else {
        final rawUserToken = result['user_token'];
        if (rawUserToken is String && rawUserToken.isNotEmpty) {
          userToken = rawUserToken;
        }
      }

      final data = result['data'];
      if (userToken == null && data is Map) {
        final rawToken = data['token'];
        if (rawToken is String && rawToken.isNotEmpty) {
          userToken = rawToken;
        } else {
          final rawUserToken = data['user_token'];
          if (rawUserToken is String && rawUserToken.isNotEmpty) {
            userToken = rawUserToken;
          }
        }
      }

      if (userToken != null) {
        AuthService.saveLocalToken(userToken);
        await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
        // 🆕 登录后初始化社交资料（清除旧缓存 → 拉新账号资料）并取消账号销毁
        await SocialService.ensureProfileAfterLogin();

        setState(() => _loginSuccess = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("登录成功 🎉")),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return;
      }

      // 后端未返回 token：若本地已有登录态则直接视为成功
      String? existingToken = AuthService.getLocalToken();
      print('当前 token: $existingToken');
      if (existingToken != null && existingToken.isNotEmpty) {
        print('✅ 已有 token，登录成功');
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
        print('⚠️ 登录成功但没有 token');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("登录成功，但未获取到凭证，请重新登录")),
        );
        _isProcessing = false;
        setState(() {});
      }
      return;
    }

    // 失败分支：展示后端返回的错误信息
    final errorMsg = (result['error'] ?? result['msg'] ?? result['message'] ?? '登录失败，请重试').toString();
    print('❌ 登录失败: $errorMsg');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorMsg)),
    );
    _isProcessing = false;
    setState(() {});
  }

  void _onDetect(BarcodeCapture capture) {
    final String? code = capture.barcodes.first.rawValue;
    if (code != null && !_isProcessing && !_loginSuccess) {
      _handleLogin(code);
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: Stack(
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
    );
  }
}
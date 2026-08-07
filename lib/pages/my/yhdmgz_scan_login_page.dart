
import 'package:flutter/material.dart';
import 'package:kazumi/services/yhdmgz_qr_protocol.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 扫描 yhdmgz://login 二维码后的处理页
/// 扫码插件只需把二维码字符串传入 handleCode 即可
class YhdmgzScanLoginPage extends StatefulWidget {
  const YhdmgzScanLoginPage({super.key});

  @override
  State<YhdmgzScanLoginPage> createState() => _YhdmgzScanLoginPageState();
}

class _YhdmgzScanLoginPageState extends State<YhdmgzScanLoginPage> {
  String message = '等待扫描二维码';

  Future<void> handleCode(String code) async {
    final token = YhdmgzQrProtocol.getToken(code);
    if (token == null) {
      setState(() => message = '不是樱花动漫登录二维码');
      return;
    }

    // 将 token 交给后端换取正式登录 token
    final result = await AuthService.getUser(token);
    if (result['token'] != null) {
      AuthService.saveLocalToken(result['token']);
      await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
      setState(() => message = '登录成功');
    } else {
      setState(() => message = '登录确认失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码登录')),
      body: Center(child: Text(message)),
    );
  }
}

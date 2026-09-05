
import 'package:flutter/material.dart';
import 'package:kazumi/services/yhdmgz_qr_protocol.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 扫描 yhdm://login 二维码后的处理页
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

    // 🔧 用 qrcode_login 确认二维码并换取正式登录 token
    // （原实现用 getUser，但 user 接口不返回 token，导致 token 永远没保存 → 同步提示登录过期）
    final result = await AuthService.qrcodeLogin(token);

    // 兼容多级结构提取 token（token / user_token / data.token）
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
      final dToken = data['token'];
      if (dToken is String && dToken.isNotEmpty) {
        userToken = dToken;
      } else {
        final dUserToken = data['user_token'];
        if (dUserToken is String && dUserToken.isNotEmpty) {
          userToken = dUserToken;
        }
      }
    }

    if (userToken != null) {
      AuthService.saveLocalToken(userToken);
      await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
      // 🆕 登录后初始化社交资料（建号分配 uid/昵称/头像）并取消账号销毁
      await SocialService.ensureProfileAfterLogin();
      setState(() => message = '登录成功');
    } else {
      setState(() => message = '登录确认失败：${result['error'] ?? '未知错误'}');
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

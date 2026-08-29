import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/request/config/api_endpoints.dart';

/// 签名校验失败页。
///
/// 独立启动（runApp 直接渲染本页），不加载主应用任何内容，因此被篡改的包
/// 用户看不到内部功能。页面无法返回，只能前往官方渠道重新下载或退出应用。
class SignatureErrorPage extends StatelessWidget {
  const SignatureErrorPage({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  void _exitApp() {
    try {
      SystemNavigator.pop();
    } catch (_) {}
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '应用校验失败',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.red.shade700, brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.gpp_bad_outlined,
                        size: 88, color: Colors.red.shade400),
                    const SizedBox(height: 20),
                    const Text(
                      '应用签名校验失败',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB71C1C)),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '当前安装包未通过官方签名校验，可能被二次打包、篡改或来自非官方渠道。\n'
                      '为保障你的账号与设备安全，本应用已停止运行。\n\n'
                      '请卸载当前版本，并从下方官方渠道重新下载安装。',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF616161)),
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: () => _open(ApiEndpoints.projectUrl),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.download),
                      label: const Text('前往官方下载', style: TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _open(ApiEndpoints.sourceUrl),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.code),
                      label: const Text('GitHub 仓库', style: TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(height: 20),
                    TextButton.icon(
                      onPressed: _exitApp,
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      icon: const Icon(Icons.power_settings_new),
                      label: const Text('退出应用',
                          style: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

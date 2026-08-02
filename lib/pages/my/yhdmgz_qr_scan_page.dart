
import 'package:flutter/material.dart';
import 'package:kazumi/services/qr_login_service.dart';

class YhdmgzQrScanPage extends StatefulWidget {
  const YhdmgzQrScanPage({super.key});

  @override
  State<YhdmgzQrScanPage> createState() => _YhdmgzQrScanPageState();
}

class _YhdmgzQrScanPageState extends State<YhdmgzQrScanPage> {
  final controller = TextEditingController();

  void _parse() async {
    final text = controller.text.trim();
    if (!QrLoginService.canHandle(text)) return;

    final token = QrLoginService.getToken(text);
    if (token == null) return;

    final ok = await QrLoginService.confirmLogin(context, token);
    if (ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("登录确认成功")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("樱花动漫扫码登录")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("扫描其他设备生成的二维码"),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "yhdmgz://login?token=xxx",
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _parse,
              child: const Text("确认扫码"),
            )
          ],
        ),
      ),
    );
  }
}

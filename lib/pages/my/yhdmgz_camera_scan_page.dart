
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:kazumi/services/qr_login_service.dart';

class YhdmgzCameraScanPage extends StatefulWidget {
  const YhdmgzCameraScanPage({super.key});

  @override
  State<YhdmgzCameraScanPage> createState() => _YhdmgzCameraScanPageState();
}

class _YhdmgzCameraScanPageState extends State<YhdmgzCameraScanPage> {
  bool done = false;

  Future<void> _scan(String value) async {
    if (done) return;
    if (!QrLoginService.canHandle(value)) return;
    done = true;

    final token = QrLoginService.getToken(value);
    if (token == null) return;

    final ok = await QrLoginService.confirmLogin(context, token);
    if (mounted && ok) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描樱花动漫二维码')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              for (final code in capture.barcodes) {
                final value = code.rawValue;
                if (value != null) _scan(value);
              }
            },
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('请扫描另一台设备显示的登录二维码'),
            ),
          )
        ],
      ),
    );
  }
}

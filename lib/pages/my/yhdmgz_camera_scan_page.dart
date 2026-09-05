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
  bool loading = false;

  Future<void> _scan(String value) async {
    if (done || loading) return;
    if (!QrLoginService.canHandle(value)) return;

    final token = QrLoginService.getToken(value);
    if (token == null) return;

    done = true;
    loading = true;
    setState(() {});

    // 扫码后直接登录，不弹确认框
    final ok = await QrLoginService.directLogin(token);

    if (!mounted) return;

    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        done = false;
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录失败，请重新扫描')),
      );
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
          if (loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';

class UpdateSettingsPage extends StatefulWidget {
  const UpdateSettingsPage({super.key});

  @override
  State<UpdateSettingsPage> createState() => _UpdateSettingsPageState();
}

class _UpdateSettingsPageState extends State<UpdateSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('检查更新'),
      ),
      body: Center(
        child: FilledButton.icon(
          onPressed: () async {
            final controller = inject<MyController>();
            await controller.checkUpdate();
          },
          icon: const Icon(Icons.system_update),
          label: const Text('检查更新'),
        ),
      ),
    );
  }
}

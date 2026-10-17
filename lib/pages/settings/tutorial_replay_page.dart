import 'package:flutter/material.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/services/tutorial/tutorial_controller.dart';
import 'package:yhdm/services/tutorial/tutorial_steps.dart';

/// 🆕 「新手引导」重看页：进入后立即开始引导，看完返回本页
class TutorialReplayPage extends StatefulWidget {
  const TutorialReplayPage({super.key});

  @override
  State<TutorialReplayPage> createState() => _TutorialReplayPageState();
}

class _TutorialReplayPageState extends State<TutorialReplayPage> {
  @override
  void initState() {
    super.initState();
    // 返回上一页后再开始引导，避免引导层被本页遮挡
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).maybePop();
      Future.delayed(const Duration(milliseconds: 400), () {
        TutorialController.instance.start(buildTutorialSteps());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: SysAppBar(title: Text('新手引导')),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_rounded, size: 56),
              SizedBox(height: 16),
              Text('正在打开新手引导…', style: TextStyle(fontSize: 16)),
              SizedBox(height: 8),
              Text(
                '如果引导没有出现，请返回再进入本页重试。',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:yhdm/services/tutorial/tutorial_controller.dart';
import 'package:yhdm/services/tutorial/tutorial_steps.dart';

/// 🆕 「新手引导」重看入口
///
/// 进入后立刻返回首页，并从第一步重新开始整个教程（不显示空白页面）。
class TutorialReplayPage extends StatefulWidget {
  const TutorialReplayPage({super.key});

  @override
  State<TutorialReplayPage> createState() => _TutorialReplayPageState();
}

class _TutorialReplayPageState extends State<TutorialReplayPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 先回到首页（popUntil root 会把本页也弹掉）
      Navigator.of(context).popUntil((route) => route.isFirst);
      // 等首页渲染稳定后再开始引导
      Future.delayed(const Duration(milliseconds: 450), () {
        TutorialController.instance.start(buildTutorialSteps());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // 本页只作为“触发入口”，不展示内容
    return const Scaffold(body: SizedBox.shrink());
  }
}

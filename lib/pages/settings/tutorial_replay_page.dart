import 'package:flutter/material.dart';
import 'package:yhdm/services/tutorial/tutorial_controller.dart';
import 'package:yhdm/services/tutorial/tutorial_steps.dart';

/// 🆕 「新手引导」重看入口（工具函数，不是页面）
///
/// 调用方（设置项点击）应该**不**再推一个空白页，而是直接调用 [startTutorialReplay]：
/// 1. 把导航栈弹回到根路由（大厅/首页）
/// 2. 等首页渲染稳定后，从头开始整个引导
void startTutorialReplay(BuildContext context) {
  final nav = Navigator.of(context, rootNavigator: true);
  // 回到根路由（大厅首页）。注意 settings 页可能 push 了多层，用 popUntil 清干净
  nav.popUntil((route) => route.isFirst);
  // 首页渲染稳定后再启动引导
  Future.delayed(const Duration(milliseconds: 500), () {
    TutorialController.instance.start(buildTutorialSteps());
  });
}

/// 兼容旧代码：如果设置页仍走 `page:` 分支（未迁移到 [startTutorialReplay]），
/// 这个空页面作为兜底，进入时自动回首页并启动引导。
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
      Navigator.of(context).popUntil((route) => route.isFirst);
      Future.delayed(const Duration(milliseconds: 500), () {
        TutorialController.instance.start(buildTutorialSteps());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.shrink());
  }
}

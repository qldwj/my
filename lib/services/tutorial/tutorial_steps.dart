import 'package:flutter/material.dart';
import 'package:yhdm/services/tutorial/tutorial_controller.dart';

/// 🆕 引导过程中用到的全局 Key（由各页面把 Key 挂到目标控件上）
class TutorialKeys {
  TutorialKeys._();
  static final ruleInstall = GlobalKey();
  static final homeSearch = GlobalKey();
  static final homeList = GlobalKey();
  static final infoStartWatch = GlobalKey();
  static final sourceSheet = GlobalKey();
  static final playButton = GlobalKey();
}

/// 🆕 新手引导步骤（7 步）
///
/// 顺序：安装规则 → 首页列表 → 右上角搜索 → 详情页 → 开始观看
///      → 选规则（颜色图例 + 点绿色源 + 选第一条结果）→ 播放
List<TutorialStep> buildTutorialSteps() {
  return [
    TutorialStep(
      title: '① 先安装规则',
      content: '规则 = 番剧来源。点右上角「+」→「新建 XPath 规则」或「浏览规则仓库」，'
          '建议多装几个（绿色表示可用），这样搜索命中率更高。',
      targetKey: TutorialKeys.ruleInstall,
    ),
    TutorialStep(
      title: '② 回到首页',
      content: '这里会展示热门番剧列表。你可以直接点任意一部进入详情页，也可以先搜索。',
      route: '/tab/popular/',
      targetKey: TutorialKeys.homeList,
    ),
    TutorialStep(
      title: '③ 右上角搜索',
      content: '想看的番不在列表里？点右上角放大镜，输入番剧名（建议用中文名）搜索。',
      targetKey: TutorialKeys.homeSearch,
    ),
    TutorialStep(
      title: '④ 打开详情页',
      content: '点任意一部番剧进入详情页。这里能看到简介、评分、吐槽，'
          '底部有「开始观看」和「发表吐槽」两个按钮。',
      targetKey: TutorialKeys.infoStartWatch,
    ),
    TutorialStep(
      title: '⑤ 点「开始观看」',
      content: '点「开始观看」后会弹出来源选择。每个源左边的小圆点代表它的状态：\n\n'
          '🟢 绿色 = 可以正常使用（优先选它）\n'
          '🟠 橙色 = 搜索不到结果\n'
          '🔵 蓝色 = 需要验证码，点进去验证后可用\n'
          '🟣 紫色 = 需要登录，登录后可用\n'
          '🔴 红色 = 搜索失败/站点异常\n\n'
          '建议：先点绿色的源。',
      targetKey: TutorialKeys.sourceSheet,
    ),
    TutorialStep(
      title: '⑥ 选第一个结果',
      content: '点绿色源后会列出它的搜索结果（比如「你的名字」）。'
          '如果有多条，选匹配度最高/第一条就行，点一下就开播。',
      targetKey: TutorialKeys.sourceSheet,
    ),
    TutorialStep(
      title: '⑦ 开始播放',
      content: '视频开始播放后，下拉可选集数，右上角可切线路、调弹幕。'
          '以后想换源，点播放页的「播放线路」即可。\n\n引导结束，祝你追番愉快！',
      targetKey: TutorialKeys.playButton,
    ),
  ];
}

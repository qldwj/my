import 'package:flutter/material.dart';
import 'package:yhdm/services/tutorial/tutorial_controller.dart';

/// 🆕 引导过程中用到的全局 Key（由各页面把 Key 挂到目标控件上）
class TutorialKeys {
  TutorialKeys._();
  /// 规则卡片上的「安装」按钮（向导页/规则仓库第一项）
  static final ruleInstall = GlobalKey();
  /// 规则管理页右上角「+」添加规则
  static final ruleAdd = GlobalKey();
  /// 首页列表第一张番剧卡
  static final homeList = GlobalKey();
  /// 首页右上角搜索
  static final homeSearch = GlobalKey();
  /// 详情页底部「发表吐槽」
  static final infoComment = GlobalKey();
  /// 详情页底部「开始观看」
  static final infoStartWatch = GlobalKey();
  /// 选源面板的源 Tab 栏
  static final sourceSheet = GlobalKey();
  /// 播放页「播放线路」条
  static final playButton = GlobalKey();
}

/// 🆕 引导事件名（由真实操作触发，推进等待中的步骤）
class TutorialEvents {
  TutorialEvents._();
  /// 安装完一条规则
  static const installedRule = 'installed_rule';
  /// 打开番剧详情页
  static const openedInfo = 'opened_info';
  /// 详情页点了「开始观看」→ 选源面板
  static const openSourceSheet = 'open_source_sheet';
  /// 选源面板点了某个源
  static const pickedSource = 'picked_source';
}

/// 🆕 新手引导步骤（跟随真实操作，逐层推进）
///
/// 顺序：安装规则 → 挑一部番 → 详情页介绍 → 开始观看 → 选绿色源 → 播放
List<TutorialStep> buildTutorialSteps() {
  return [
    TutorialStep(
      title: '① 先安装规则',
      content: '规则 = 番剧来源。请点击高亮的「安装」按钮安装一条规则。\n'
          '建议多装几条（可用源越多，搜番命中率越高）。',
      targetKey: TutorialKeys.ruleInstall,
    ),
    TutorialStep(
      title: '② 挑一部想看的番',
      content: '安装完成后点「下一步」。首页会展示热门番剧，'
          '请点击高亮的那一部（或自己挑一部）进入详情页。',
      route: '/tab/popular/',
      targetKey: TutorialKeys.homeList,
    ),
    TutorialStep(
      title: '③ 详情页介绍',
      content: '这一页是番剧介绍：上方有简介、评分，往下可看角色、关联作品。\n'
          '高亮的是「发表吐槽」（查看/发表评论）。准备好后点「下一步」。',
      targetKey: TutorialKeys.infoComment,
    ),
    TutorialStep(
      title: '④ 点「开始观看」',
      content: '现在请点高亮的「开始观看」按钮，进入播放源选择。\n\n'
          '来源状态颜色：\n'
          '🟢 绿色 = 可正常使用（优先选）\n'
          '🔵 蓝色 = 需验证码（点进去验证后可用）\n'
          '🟣 紫色 = 需登录（登录后可用）\n'
          '🟠 橙色 = 搜不到结果\n'
          '🔴 红色 = 搜索失败/站点异常',
      targetKey: TutorialKeys.infoStartWatch,
    ),
    TutorialStep(
      title: '⑤ 选一个绿色源',
      content: '选源面板已打开。请点一个🟢绿色圆点的源（可正常使用），'
          '优先选匹配度高的。点击后会列出它的搜索结果，选第一条即开播。',
      targetKey: TutorialKeys.sourceSheet,
    ),
    TutorialStep(
      title: '⑥ 开始播放',
      content: '视频开始播放后，下拉可切集数，右上角可切线路、调弹幕。\n'
          '以后想换源，点播放页的「播放线路」即可。\n\n引导结束，祝你追番愉快！',
      targetKey: TutorialKeys.playButton,
    ),
  ];
}

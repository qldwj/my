import 'package:flutter/material.dart';

/// 🆕 新手引导（聚光灯式）的一个步骤
class TutorialStep {
  const TutorialStep({
    required this.title,
    required this.content,
    this.targetKey,
    this.route,
    this.highlightPadding = 8,
    this.advanceEvent,
    this.showNextButton = true,
  });

  /// 步骤标题
  final String title;

  /// 步骤正文（说明这一步要做什么）
  final String content;

  /// 要高亮的控件 Key（挂在目标按钮/区域上）；为空则居中显示气泡
  final GlobalKey? targetKey;

  /// 点击「下一步」时先跳转到的路由（为空则不跳转）
  /// 例如首页要跳到详情页时填 '/info/'。
  final String? route;

  /// 高亮挖孔相对目标的外扩像素
  final double highlightPadding;

  /// 🆕 等待某个“真实操作事件”才推进。
  /// 非空时该步不靠点「下一步」，而是等 [TutorialController.notifyEvent] 触发，
  /// 例如用户真的点开了选源面板（事件名 'open_source_sheet'）。
  final String? advanceEvent;

  /// 🆕 是否显示「下一步」按钮。等待真实操作的步骤通常设为 false。
  final bool showNextButton;
}

/// 🆕 新手引导控制器（全局单例）
///
/// - [start] 开始引导；[next] 下一步；[prev] 上一步；[finish] 结束
/// - [notifyEvent] 收到真实操作事件时推进（用于 advanceEvent 步骤）
/// - 内部用 [ChangeNotifier] 驱动 `TutorialOverlay` 重绘
class TutorialController extends ChangeNotifier {
  TutorialController._();
  static final TutorialController instance = TutorialController._();

  List<TutorialStep> _steps = const [];
  int _index = 0;
  bool _active = false;

  /// 每个步骤进入前要执行的跳转回调（由 Overlay 注入，因为需要 Navigator）
  void Function(String route)? onNavigate;

  bool get active => _active;
  int get index => _index;
  int get total => _steps.length;
  TutorialStep? get current =>
      (_active && _index >= 0 && _index < _steps.length) ? _steps[_index] : null;

  /// 开始引导；[steps] 为步骤列表
  void start(List<TutorialStep> steps) {
    if (steps.isEmpty) return;
    _steps = steps;
    _index = 0;
    _active = true;
    notifyListeners();
  }

  /// 手动下一步（最后一步时结束）
  TutorialStep? next() {
    if (!_active) return null;
    if (_index >= _steps.length - 1) {
      finish();
      return null;
    }
    _index++;
    notifyListeners();
    return _steps[_index];
  }

  /// 🆕 收到真实操作事件时调用：若当前步骤正等待该事件，则推进。
  /// 返回是否消费了该事件。
  bool notifyEvent(String event) {
    if (!_active) return false;
    final step = current;
    if (step?.advanceEvent != null && step!.advanceEvent == event) {
      next();
      return true;
    }
    return false;
  }

  /// 上一步
  TutorialStep? prev() {
    if (!_active || _index <= 0) return null;
    _index--;
    notifyListeners();
    return _steps[_index];
  }

  /// 结束（完成或跳过）
  void finish() {
    _active = false;
    _steps = const [];
    _index = 0;
    notifyListeners();
  }
}

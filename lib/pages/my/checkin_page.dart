import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/checkin_service.dart';

/// 🆕 追番打卡 / 连看天数页面
class CheckinPage extends StatefulWidget {
  const CheckinPage({super.key});

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  bool _loading = true;
  bool _checking = false;
  int _streak = 0;
  int _total = 0;
  int _coins = 0;
  bool _checkedToday = false;
  String _today = '';
  List<String> _calendar = [];
  List<Map<String, dynamic>> _achievements = [];
  int _unlockedCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await CheckinService.stats();
    if (!mounted) return;
    if (res['error'] != null) {
      setState(() => _loading = false);
      if (res['error'] == '未登录') {
        KazumiDialog.showToast(message: '请先登录');
      } else {
        KazumiDialog.showToast(message: '加载失败：${res['error']}');
      }
      return;
    }
    setState(() {
      _streak = res['streak'] is int ? res['streak'] as int : 0;
      _total = res['total'] is int ? res['total'] as int : 0;
      _coins = res['coins'] is int ? res['coins'] as int : 0;
      _checkedToday = res['checkedToday'] == true;
      _today = res['today']?.toString() ?? '';
      _calendar = (res['calendar'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _loading = false;
    });
    await _loadAchievements();
  }

  Future<void> _loadAchievements() async {
    final res = await CheckinService.achievements();
    if (!mounted) return;
    if (res['error'] != null || res['achievements'] == null) return;
    final list = (res['achievements'] as List).cast<Map>();
    var unlocked = 0;
    for (final a in list) {
      if (a['unlocked'] == true) unlocked++;
    }
    setState(() {
      _achievements = list.map((e) => Map<String, dynamic>.from(e)).toList();
      _unlockedCount = unlocked;
    });
  }

  Future<void> _checkin() async {
    if (_checking) return;
    setState(() => _checking = true);
    final res = await CheckinService.checkin();
    if (!mounted) return;
    setState(() => _checking = false);
    if (res['error'] != null) {
      KazumiDialog.showToast(message: '打卡失败：${res['error']}');
      return;
    }
    KazumiDialog.showToast(
        message: res['checked'] == true ? '打卡成功 ✅ +5 积分' : '今天已打卡过啦');
    await _load();
  }

  Future<void> _share() async {
    final res = await CheckinService.share();
    if (!mounted) return;
    if (res['error'] != null) {
      KazumiDialog.showToast(message: '分享失败：${res['error']}');
      return;
    }
    final text = res['text']?.toString() ?? '';
    // 复制到剪贴板
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    KazumiDialog.showToast(message: '打卡文案已复制');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('追番打卡')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 连看天数大卡
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text('连续追番',
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('$_streak',
                              style: TextStyle(
                                fontSize: 52,
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary)),
                          const SizedBox(width: 6),
                          Text('天',
                              style: TextStyle(
                                  fontSize: 18, color: cs.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('今日 $_today · 累计 $_total 天 · 积分 $_coins',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 打卡按钮
                FilledButton.icon(
                  onPressed: _checkedToday ? null : _checkin,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(_checkedToday
                      ? Icons.check_circle_rounded
                      : Icons.local_fire_department_rounded),
                  label: Text(_checkedToday ? '今天已打卡' : (_checking ? '打卡中…' : '今天打卡 +5 积分')),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('分享打卡'),
                ),
                const SizedBox(height: 20),
                Text('最近 60 天',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                const SizedBox(height: 8),
                _buildCalendar(cs),
                const SizedBox(height: 24),
                // 🆕 成就系统
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('成就系统',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    Text('$_unlockedCount / ${_achievements.length} 已解锁',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 8),
                if (_achievements.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    alignment: Alignment.center,
                    child: Text('成就加载中…', style: TextStyle(fontSize: 12, color: cs.outline)),
                  )
                else
                  _buildAchievementGrid(cs),
              ],
            ),
    );
  }

  /// 🆕 成就网格（每行 3 个，解锁彩色 / 未解锁灰色）
  Widget _buildAchievementGrid(ColorScheme cs) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.92,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _achievements.length,
      itemBuilder: (_, i) {
        final a = _achievements[i];
        final unlocked = a['unlocked'] == true;
        final cur = a['current'] is int ? a['current'] as int : 0;
        final target = a['target'] is int ? a['target'] as int : 0;
        final icon = a['icon']?.toString() ?? '🏅';
        final name = a['name']?.toString() ?? '';
        final desc = a['desc']?.toString() ?? '';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: unlocked
                ? cs.primaryContainer.withOpacity(0.55)
                : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: unlocked ? Border.all(color: cs.primary, width: 1) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: unlocked ? 1 : 0.35,
                child: Text(icon, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(height: 4),
              Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: unlocked ? cs.onSurface : cs.onSurfaceVariant,
                  )),
              const SizedBox(height: 2),
              Text(unlocked ? '已解锁' : '$cur/$target',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: unlocked ? cs.primary : cs.outline,
                  )),
              const SizedBox(height: 2),
              Text(desc,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: cs.outline)),
            ],
          ),
        );
      },
    );
  }

  /// 近 60 天打卡日历（打卡日期高亮）
  Widget _buildCalendar(ColorScheme cs) {
    final checked = _calendar.toSet();
    final today = DateTime.now();
    final cells = <Widget>[];
    for (int i = 59; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final hit = checked.contains(key);
      final isToday = i == 0;
      cells.add(Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: hit ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: cs.primary, width: 1.5)
              : null,
        ),
        child: Center(
          child: Text(
            '${d.day}',
            style: TextStyle(
              fontSize: 12,
              color: hit ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ));
    }
    return GridView.count(
      crossAxisCount: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }
}

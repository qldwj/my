import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/bean/card/network_img_layer.dart';
import 'package:yhdm/services/checkin_service.dart';

/// 🆕 打卡排行榜：按连续签到天数排（中断归零），每周一凌晨结算，前三名奖励 300/200/100 积分
class CheckinRankPage extends StatefulWidget {
  const CheckinRankPage({super.key});

  @override
  State<CheckinRankPage> createState() => _CheckinRankPageState();
}

class _CheckinRankPageState extends State<CheckinRankPage> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _list = [];
  Map<String, dynamic>? _me;
  Map<String, dynamic>? _reward;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await CheckinService.rank();
    if (!mounted) return;
    if (res['error'] != null) {
      setState(() {
        _loading = false;
        _error = res['error'].toString();
      });
      return;
    }
    setState(() {
      _list = (res['list'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      _me = res['me'] is Map
          ? Map<String, dynamic>.from(res['me'] as Map)
          : null;
      _reward = res['reward'] is Map
          ? Map<String, dynamic>.from(res['reward'] as Map)
          : null;
      _loading = false;
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
          ),
          title: const Text('打卡排行榜'),
        ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text('加载失败：$_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildRewardBanner(cs),
                      const SizedBox(height: 12),
                      if (_me != null) _buildMeCard(cs),
                      const SizedBox(height: 12),
                      if (_list.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('暂无榜单数据，快去打卡吧'),
                          ),
                        )
                      else
                        ..._list.asMap().entries.map(
                            (e) => _buildRow(cs, e.key, e.value)),
                    ],
                  ),
                ),
    );
  }

  /// 返回上一页（回打卡页，一层一层返回）；系统返回与左上角按钮统一走这里
  void _goBack() {
    if (!mounted) return;
    context.maybePop();
  }

  Widget _buildRewardBanner(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Text('每周奖励',
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          Text('按连续签到天数排名（中断归零），每周一凌晨结算：',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text('🥇 第1名 +300积分    🥈 第2名 +200积分    🥉 第3名 +100积分',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (_reward != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '本周已结算：第 ${_rankLabel(_reward!['uid'])} 名 +${_reward!['coins']} 积分',
                style: TextStyle(fontSize: 12, color: cs.primary),
              ),
            ),
        ],
      ),
    );
  }

  String _rankLabel(dynamic uid) {
    for (final it in _list) {
      if (it['uid'] == uid) return '${it['rank']}';
    }
    return '?';
  }

  Widget _buildMeCard(ColorScheme cs) {
    final me = _me!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.person_rounded, color: cs.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text('我的排名：第 ${me['rank']} 名',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text('连续 ${me['streak']} 天',
              style: TextStyle(fontSize: 13, color: cs.onSecondaryContainer)),
        ],
      ),
    );
  }

  Widget _buildRow(ColorScheme cs, int index, Map<String, dynamic> item) {
    final rank = item['rank'] as int;
    final nickname = (item['nickname'] as String?)?.isNotEmpty == true
        ? item['nickname'] as String
        : '番友${item['uid']}';
    final avatar = item['avatar'] as String? ?? '';
    final streak = item['streak'] as int? ?? 0;
    final title = item['title'] as String? ?? '';
    final isMe = item['me'] == true;

    Color? rankColor;
    String rankIcon = '';
    if (rank == 1) {
      rankColor = const Color(0xFFD4AF37);
      rankIcon = '🥇';
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0);
      rankIcon = '🥈';
    } else if (rank == 3) {
      rankColor = const Color(0xFFCD7F32);
      rankIcon = '🥉';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color:
            isMe ? cs.primaryContainer.withOpacity(0.4) : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: isMe ? Border.all(color: cs.primary, width: 1) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: rankIcon.isNotEmpty
                ? Text(rankIcon, style: const TextStyle(fontSize: 22))
                : Text('$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: cs.outline)),
          ),
          ClipOval(
            child: avatar.isNotEmpty
                ? NetworkImgLayer(width: 40, height: 40, src: avatar)
                : Container(
                    width: 40,
                    height: 40,
                    color: cs.surfaceContainerHighest,
                    child: Icon(Icons.person_rounded,
                        color: cs.onSurfaceVariant),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (title.isNotEmpty)
                  Text(title, style: TextStyle(fontSize: 11, color: cs.outline)),
              ],
            ),
          ),
          if (isMe)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('我',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.primary,
                      fontWeight: FontWeight.w700)),
            ),
          Text('连续 $streak 天',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: rankColor ?? cs.onSurface)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 隐私设置页（我的 → 隐私设置）
///
/// 三个开关，默认全部关闭（保护隐私）：
/// - 允许他人查看我的主页
/// - 允许他人查看我的资料（介绍/性别/生日）
/// - 允许他人添加我为好友
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});
  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _allowViewProfile = false;
  bool _allowViewInfo = false;
  bool _allowAddFriend = false;
  bool _loading = true;
  bool _saving = false;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SocialService.getProfile(refresh: true);
      if (!mounted) return;
      setState(() {
        _allowViewProfile = p?.allowViewProfile ?? false;
        _allowViewInfo = p?.allowViewInfo ?? false;
        _allowAddFriend = p?.allowAddFriend ?? false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final err = await SocialService.updatePrivacy(
      allowViewProfile: _allowViewProfile,
      allowViewInfo: _allowViewInfo,
      allowAddFriend: _allowAddFriend,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      KazumiDialog.showToast(message: err);
    } else {
      KazumiDialog.showToast(message: '隐私设置已保存');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私设置'),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中...' : '保存'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 说明
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.privacy_tip_outlined, color: Colors.blue.shade600),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '默认全部关闭以保护你的隐私。\n开启后，其他用户可以查看你的主页/资料或添加你为好友。',
                          style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _buildSwitchTile(
                  icon: Icons.home_outlined,
                  title: '允许查看我的主页',
                  desc: '开启后，其他用户可以从评论/好友列表进入你的主页',
                  value: _allowViewProfile,
                  onChanged: (v) => setState(() => _allowViewProfile = v),
                ),
                _buildSwitchTile(
                  icon: Icons.badge_outlined,
                  title: '允许查看我的资料',
                  desc: '开启后，其他用户可查看你的个人介绍、性别、生日',
                  value: _allowViewInfo,
                  onChanged: (v) => setState(() => _allowViewInfo = v),
                ),
                _buildSwitchTile(
                  icon: Icons.person_add_alt_1,
                  title: '允许添加我为好友',
                  desc: '开启后，其他用户可以向您发送好友申请',
                  value: _allowAddFriend,
                  onChanged: (v) => setState(() => _allowAddFriend = v),
                ),

                const SizedBox(height: 24),
                // 保存按钮
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_saving ? '保存中...' : '保存设置'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 16),

                // 隐私状态提示
                if (!_allowViewProfile)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '当前状态：隐私用户（其他人无法查看你的主页）',
                            style: TextStyle(fontSize: 12, color: cs.outline),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        secondary: Icon(icon, color: cs.primary),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        subtitle: Text(desc, style: TextStyle(fontSize: 12, color: cs.outline)),
        value: value,
        onChanged: onChanged,
        activeTrackColor: cs.primary,
      ),
    );
  }
}
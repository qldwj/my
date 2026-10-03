import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/account_status_cache.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/checkin_service.dart';
import 'package:kazumi/services/social/social_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:url_launcher/url_launcher.dart';

/// 账号页面（编辑个人资料）
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});
  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  SocialProfile? _profile;
  Map<String, bool> _status = {
    'has_qq': false, 'has_wechat': false,
    'has_telegram': false, 'has_douyin': false,
  };
  bool _uploading = false;
  String _currentTitle = '';
  List<Map<String, dynamic>> _unlockedTitles = [];

  @override
  void initState() {
    super.initState();
    _profile = SocialService.restoreLocalProfile();
    // 🆕 先用本地 Hive 缓存渲染，避免每次进页面都等服务器 login_status
    final cached = AccountStatusCache.readStatus();
    if (cached != null) {
      _status = {
        'has_qq': cached['has_qq'] == true,
        'has_wechat': cached['has_wechat'] == true,
        'has_telegram': cached['has_telegram'] == true,
        'has_douyin': cached['has_douyin'] == true,
      };
    }
    _loadStatus();
    _loadTitle();
  }

  Future<void> _loadStatus() async {
    // 🆕 5 分钟内已有本地缓存就不再打服务器
    if (!AccountStatusCache.shouldRefresh && AccountStatusCache.readStatus() != null) {
      return;
    }
    try {
      final token = AuthService.getLocalToken();
      if (token == null) return;
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(
        Uri.parse('https://qlyyz.xyz/api/v1/login?action=login_status'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $token');
      request.add(utf8.encode('{}'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['success'] == true && mounted) {
        final d = data['data'] as Map<String, dynamic>? ?? {};
        setState(() {
          _status = {
            'has_qq': d['has_qq'] ?? false,
            'has_wechat': d['has_wechat'] ?? false,
            'has_telegram': d['has_telegram'] ?? false,
            'has_douyin': d['has_douyin'] ?? false,
          };
        });
        // 🆕 落到 Hive，下次进页面秒显示
        AccountStatusCache.saveStatus(Map<String, dynamic>.from(d));
      }
    } catch (_) {}
  }

  Future<void> _pickAvatar() async {
    if (_uploading) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      KazumiDialog.showToast(message: '图片过大（最大 2MB）');
      return;
    }
    setState(() => _uploading = true);
    final error = await SocialService.uploadAvatar(base64Encode(bytes));
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _profile = SocialService.myProfile;
    });
    if (error == null) {
      KazumiDialog.showToast(message: '头像已更新');
    } else {
      KazumiDialog.showToast(message: '$error');
    }
  }

  void _editNickname() {
    final ctrl = TextEditingController(text: _profile?.nickname ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: ctrl, maxLength: 20,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            final name = ctrl.text.trim();
            if (name.isEmpty) return;
            final error = await SocialService.updateProfile(nickname: name);
            if (!mounted) return;
            Navigator.pop(ctx);
            if (error == null) {
              setState(() => _profile = SocialService.myProfile);
              KazumiDialog.showToast(message: '昵称已更新');
            }
          }, child: const Text('保存')),
        ],
      ),
    );
  }

  void _editBio() {
    final ctrl = TextEditingController(text: _profile?.bio ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改个人介绍'),
        content: TextField(
          controller: ctrl, maxLength: 200, maxLines: 3,
          decoration: const InputDecoration(
            hintText: '介绍一下自己吧（最多200字）',
            border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            final bio = ctrl.text.trim();
            final error = await SocialService.updateProfile(bio: bio);
            if (!mounted) return;
            Navigator.pop(ctx);
            if (error == null) {
              setState(() => _profile = SocialService.myProfile);
              KazumiDialog.showToast(message: '个人介绍已更新');
            } else {
              KazumiDialog.showToast(message: error);
            }
          }, child: const Text('保存')),
        ],
      ),
    );
  }

  void _editGender() {
    const genders = [
      (0, '保密'),
      (1, '男'),
      (2, '女'),
      (3, '其他'),
    ];
    final current = _profile?.gender ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择性别'),
        children: genders.map((g) => SimpleDialogOption(
          onPressed: () async {
            final error = await SocialService.updateProfile(gender: g.$1);
            if (!mounted) return;
            Navigator.pop(ctx);
            if (error == null) {
              setState(() => _profile = SocialService.myProfile);
              KazumiDialog.showToast(message: '性别已更新');
            } else {
              KazumiDialog.showToast(message: error);
            }
          },
          child: Row(children: [
            Icon(current == g.$1 ? Icons.check_circle : Icons.circle_outlined,
              size: 18, color: current == g.$1
                ? Theme.of(context).colorScheme.primary : Colors.grey),
            const SizedBox(width: 12),
            Text(g.$2),
          ]),
        )).toList(),
      ),
    );
  }

  void _editBirthday() async {
    final now = DateTime.now();
    final initial = _profile?.birthday.isNotEmpty == true
        ? DateTime.tryParse(_profile!.birthday)
        : null;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1950, 1, 1),
      lastDate: now,
      helpText: '选择生日',
    );
    if (picked == null || !mounted) return;
    final dateStr = '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    final error = await SocialService.updateProfile(birthday: dateStr);
    if (!mounted) return;
    if (error == null) {
      setState(() => _profile = SocialService.myProfile);
      KazumiDialog.showToast(message: '生日已更新');
    } else {
      KazumiDialog.showToast(message: error);
    }
  }

  void _editEmail() {
    final emailCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    var sending = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('绑定邮箱'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'QQ 邮箱', hintText: 'xxx@qq.com', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: codeCtrl, keyboardType: TextInputType.number,
                maxLength: 6, decoration: const InputDecoration(labelText: '验证码', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: sending ? null : () async {
                  setDialogState(() => sending = true);
                  await AuthService.sendCode(emailCtrl.text.trim());
                  setDialogState(() => sending = false);
                  KazumiDialog.showToast(message: '验证码已发送');
                },
                child: Text(sending ? '发送中...' : '发送验证码')),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () async {
              final res = await AuthService.bindEmail(
                email: emailCtrl.text.trim(), code: codeCtrl.text.trim(), captchaAnswer: '');
              if (res['success'] == true) {
                Navigator.pop(ctx);
                await AuthService.saveUserEmail(emailCtrl.text.trim());
                KazumiDialog.showToast(message: '邮箱绑定成功');
              } else {
                KazumiDialog.showToast(message: res['error'] ?? '绑定失败');
              }
            }, child: const Text('确认')),
          ],
        ),
      ),
    );
  }

  void _unbindProvider(String provider, String name) async {
    final confirm = await KazumiDialog.show<bool>(
      builder: (ctx) => AlertDialog(
        title: Text('解绑 $name'),
        content: Text('确定解绑 $name 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text('解绑', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final token = AuthService.getLocalToken();
      if (token == null) return;
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(
        Uri.parse('https://qlyyz.xyz/api/v1/login?action=unbind_provider'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $token');
      request.add(utf8.encode(jsonEncode({'provider': provider})));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['success'] == true) {
        await AccountStatusCache.clear();   // 🆕 状态变了，缓存作废
        _loadStatus();
        KazumiDialog.showToast(message: '$name 已解绑');
      } else {
        KazumiDialog.showToast(message: data['error'] ?? '解绑失败');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '网络错误');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final email = AuthService.currentUserEmail ?? '';
    final isTempEmail = email.contains('@qq.login') || email.contains('@wechat.login')
        || email.contains('@telegram.login') || email.contains('@douyin.login');
    final displayEmail = isTempEmail ? '未绑定邮箱' : email;
    final token = AuthService.getLocalToken() ?? '';
    final maskedToken = token.length > 16
        ? '${token.substring(0, 8)}****${token.substring(token.length - 8)}'
        : '****';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('账号'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 头像
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: cs.primaryContainer,
                  child: _profile?.avatar.isNotEmpty == true
                      ? ClipOval(child: NetworkImgLayer(
                          width: 80, height: 80,
                          src: SocialService.proxiedAvatar(_profile!.avatar)))
                      : Icon(Icons.person, size: 40, color: cs.onPrimaryContainer),
                ),
                Positioned(right: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                    child: _uploading
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                  )),
              ]),
            ),
          ),
          const SizedBox(height: 24),

          // 昵称
          _infoTile('昵称', _profile?.nickname ?? '未设置', onTap: _editNickname),
          const Divider(height: 1),
          // 个人介绍
          _infoTile('个人介绍', _profile?.bio.isNotEmpty == true ? _profile!.bio : '未填写', onTap: _editBio),
          const Divider(height: 1),
          // 性别
          _infoTile('性别', _profile?.genderText ?? '保密', onTap: _editGender),
          const Divider(height: 1),
          // 生日
          _infoTile('生日', _profile?.birthday.isNotEmpty == true ? _profile!.birthday : '未填写', onTap: _editBirthday),
          const Divider(height: 1),
          // 邮箱
          _infoTile('邮箱', displayEmail, onTap: _editEmail),
          const Divider(height: 1),
          // 用户 ID
          _infoTile('用户ID', maskedToken, onTap: () {
            Clipboard.setData(ClipboardData(text: token));
            KazumiDialog.showToast(message: '已复制 Token');
          }),
          const Divider(height: 1),
          // 称号
          _infoTile('称号', _currentTitle.isNotEmpty ? _currentTitle : '未解锁', onTap: _pickTitle),
          const SizedBox(height: 16),

          // 隐私设置（默认全部开启）
          Text('隐私设置', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: cs.primary)),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 0),
            title: const Text('允许查看我的主页', style: TextStyle(fontSize: 14)),
            value: _profile?.allowViewProfile ?? true,
            onChanged: (v) => _updatePrivacy('allowViewProfile', v),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 0),
            title: const Text('允许查看我的资料', style: TextStyle(fontSize: 14)),
            value: _profile?.allowViewInfo ?? true,
            onChanged: (v) => _updatePrivacy('allowViewInfo', v),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 0),
            title: const Text('允许添加我为好友', style: TextStyle(fontSize: 14)),
            value: _profile?.allowAddFriend ?? true,
            onChanged: (v) => _updatePrivacy('allowAddFriend', v),
          ),
          const SizedBox(height: 16),

          // 第三方账号
          Text('第三方账号', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: cs.primary)),
          const SizedBox(height: 8),
          _providerTile('assets/images/icons/qq.png', 'QQ', _status['has_qq']!, 'qq'),
          _providerTile('assets/images/icons/wechat.png', '微信', _status['has_wechat']!, 'wechat'),
          _providerTile('assets/images/icons/telegram.png', 'Telegram', _status['has_telegram']!, 'telegram'),
          _providerTile('assets/images/icons/douyin.png', '抖音', _status['has_douyin']!, 'douyin'),
        ],
      ),
    );
  }

  Future<void> _loadTitle() async {
    final cached = CheckinService.cachedAchievements();
    if (cached != null && mounted) {
      setState(() {
        _currentTitle = (cached['title'] is Map
            ? (cached['title']['name'] as String? ?? '')
            : '');
        _unlockedTitles = ((cached['unlockedTitles'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    }
    final res = await CheckinService.achievements();
    if (mounted && res['error'] == null) {
      setState(() {
        _currentTitle = (res['title'] is Map
            ? (res['title']['name'] as String? ?? '')
            : '');
        _unlockedTitles = ((res['unlockedTitles'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    }
  }

  Future<void> _pickTitle() async {
    if (_unlockedTitles.isEmpty) {
      KazumiDialog.showToast(message: '暂无已解锁称号，去打卡或追番解锁吧');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('选择称号'),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: _unlockedTitles.map((t) {
                final name = t['name'] as String? ?? '';
                final icon = t['icon'] as String? ?? '';
                final selected = name == _currentTitle;
                return ListTile(
                  leading: Text(icon, style: const TextStyle(fontSize: 22)),
                  title: Text(name),
                  trailing: selected
                      ? Icon(Icons.check_circle, color: cs.primary)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (name.isEmpty || selected) return;
                    final res = await CheckinService.setTitle(name);
                    if (res['success'] == true && mounted) {
                      setState(() => _currentTitle = name);
                      await CheckinService.achievements();
                      KazumiDialog.showToast(message: '称号已更新');
                    } else {
                      KazumiDialog.showToast(
                          message: res['error'] ?? '设置失败');
                    }
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _updatePrivacy(String key, bool v) async {    final err = await SocialService.updatePrivacy(
      allowViewProfile: key == 'allowViewProfile' ? v : null,
      allowViewInfo: key == 'allowViewInfo' ? v : null,
      allowAddFriend: key == 'allowAddFriend' ? v : null,
    );
    if (err != null) {
      KazumiDialog.showToast(message: err);
      return;
    }
    final fresh = await SocialService.getProfile(refresh: true);
    if (mounted && fresh != null) setState(() => _profile = fresh);
  }

  Widget _infoTile(String label, String value, {VoidCallback? onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(value, style: const TextStyle(fontSize: 15)),
      trailing: onTap != null ? const Icon(Icons.chevron_right, size: 20) : null,
      onTap: onTap,
    );
  }

  Widget _providerTile(String iconPath, String name, bool bound, String provider) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: Image.asset(iconPath, width: 28, height: 28),
      title: Text(name),
      trailing: bound
          ? OutlinedButton(
              onPressed: () => _unbindProvider(provider, name),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(60, 32),
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              child: const Text('解绑', style: TextStyle(fontSize: 12)),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
              child: const Text('未绑定', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
    );
  }
}

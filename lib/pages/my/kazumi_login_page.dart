import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/pages/my/chat_room_page.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/pages/my/qrcode_login_page.dart'; // 生成二维码页面
import 'package:kazumi/pages/my/yhdmgz_qr_scan_page.dart'; // 扫码页面

/// 樱花动漫账号登录页（验证码登录，无需密码）
class KazumiLoginPage extends StatefulWidget {
  const KazumiLoginPage({super.key});

  @override
  State<KazumiLoginPage> createState() => _KazumiLoginPageState();
}

class _KazumiLoginPageState extends State<KazumiLoginPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _captchaController = TextEditingController();
  bool _sending = false;
  bool _logging = false;
  bool _syncing = false;
  String? _captchaChallenge;
  bool _loggedIn = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loggedIn = AuthService.isLoggedIn;
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!email.endsWith('@qq.com')) {
      KazumiDialog.showToast(message: '请使用 QQ 邮箱');
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await AuthService.sendCode(email);
      if (res['captcha_challenge'] != null) {
        setState(() => _captchaChallenge = res['captcha_challenge']);
        KazumiDialog.showToast(message: '验证码已发送');
      } else {
        KazumiDialog.showToast(message: res['error'] ?? '发送失败');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '网络错误: $e');
    }
    setState(() => _sending = false);
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final captcha = _captchaController.text.trim();
    if (code.length != 6) {
      KazumiDialog.showToast(message: '请输入6位验证码');
      return;
    }
    setState(() => _logging = true);
    try {
      final res = await AuthService.login(
        email: email,
        code: code,
        captchaAnswer: captcha,
      );
      if (res['token'] != null) {
        AuthService.saveLocalToken(res['token']);
        await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
        setState(() => _loggedIn = true);
        KazumiDialog.showToast(message: '登录成功 🎉');
        Navigator.of(context).pop(true);
      } else {
        KazumiDialog.showToast(message: res['error'] ?? '登录失败');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '网络错误: $e');
    }
    setState(() => _logging = false);
  }

  void _logout() {
    AuthService.clearLocalToken();
    GStorage.putSetting(SettingsKeys.kazumiSyncEnable, false);
    setState(() => _loggedIn = false);
    KazumiDialog.showToast(message: '已退出登录');
  }

  /// 跳转到扫码页面（未登录时使用）
  void _gotoScan() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const YhdmgzQrScanPage()),
    );
  }

  /// 跳转到生成二维码页面（已登录时使用）
  void _gotoGenerateQr() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrcodeLoginPage()),
    );
  }

  /// 双向同步收藏
  Future<void> _syncCollect() async {
    setState(() => _syncing = true);
    try {
      // 30 秒超时保护
      await Future.any([
        _doSync(),
        Future.delayed(const Duration(seconds: 30), () => throw '同步超时，请检查网络'),
      ]);
    } catch (e) {
      KazumiDialog.dismiss();
      KazumiDialog.showToast(message: '❌ $e');
      KazumiLogger().e('同步失败', error: e);
    }
    setState(() => _syncing = false);
  }

  /// 核心同步逻辑（先拉取云端，再上传本地差异）
  Future<void> _doSync() async {
    try {
      KazumiDialog.showLoading(msg: '正在获取云端收藏...');

      // ---------- 第一步：拉取云端数据（使用只读接口） ----------
      final remoteRes = await AuthService.getRemoteCollect(); // ✅ 改用只读接口
      if (remoteRes['error'] != null) {
        KazumiDialog.dismiss();
        KazumiDialog.showToast(message: '❌ 获取云端数据失败: ${remoteRes['error']}');
        return;
      }

      // 解析云端收藏列表（新接口直接返回 collect 数组）
      List<dynamic> remoteList = [];
      if (remoteRes['collect'] is List) {
        remoteList = remoteRes['collect'] as List;
      } else {
        // 兼容旧格式（以防后端返回 sync_data 结构）
        if (remoteRes['sync_data'] is Map && remoteRes['sync_data']['collect'] is List) {
          remoteList = remoteRes['sync_data']['collect'] as List;
        } else {
          remoteList = [];
        }
      }

      // ---------- 第二步：下载本地缺失的条目 ----------
      int downloadCount = 0;
      final localCollectBefore = GStorage.collectibles.values.toList();
      final localIds = localCollectBefore.map((c) => c.bangumiItem.id).toSet();

      for (final item in remoteList) {
        if (item is! Map) continue;
        final remoteId = item['id'];
        if (remoteId is! int) continue;
        if (!localIds.contains(remoteId)) {
          // 构建 BangumiItem（根据服务器返回字段映射）
          final bangumiItem = BangumiItem(
            id: remoteId,
            type: 0,
            name: item['name']?.toString() ?? '未知',
            nameCn: item['name_cn']?.toString() ?? '',
            summary: item['summary']?.toString() ?? '',
            airDate: item['air_date']?.toString() ?? '',
            airWeekday: 0,
            rank: 0,
            images: {'large': item['image']?.toString() ?? ''},
            tags: [],
            alias: [],
            ratingScore: (item['rating'] as num?)?.toDouble() ?? 0.0,
            votes: 0,
            votesCount: [],
            info: '',
          );
          await GStorage.putCollectible(
            CollectedBangumi(
              bangumiItem,
              DateTime.now(),
              item['type'] is int ? item['type'] as int : 1,
            ),
          );
          downloadCount++;
        }
      }

      // ---------- 第三步：计算本地多余条目（本地有，云端没有） ----------
      final localCollectAfter = GStorage.collectibles.values.toList();
      final remoteIds = remoteList.map((e) => (e as Map)['id'] as int).toSet();

      final diffList = localCollectAfter
          .where((c) => !remoteIds.contains(c.bangumiItem.id))
          .map((c) => {
                'id': c.bangumiItem.id,
                'name': c.bangumiItem.name,
                'name_cn': c.bangumiItem.nameCn,
                'type': c.type,
                'time': c.time.toIso8601String(),
                'image': c.bangumiItem.images['large'] ?? '',
                'summary': c.bangumiItem.summary,
                'rating': c.bangumiItem.ratingScore,
              })
          .toList();

      int uploadCount = 0;
      if (diffList.isNotEmpty) {
        // ---------- 第四步：上传差异部分 ----------
        KazumiDialog.showLoading(msg: '正在上传新增条目...');
        final uploadRes = await AuthService.syncData({'collect': diffList});
        if (uploadRes['error'] != null) {
          KazumiDialog.dismiss();
          KazumiDialog.showToast(message: '❌ 上传差异失败: ${uploadRes['error']}');
          return;
        }
        uploadCount = diffList.length;
      }

      // ---------- 完成 ----------
      KazumiDialog.dismiss();
      KazumiDialog.showToast(
        message: '同步完成 ✅ 下载 $downloadCount 项，上传 $uploadCount 项',
      );

    } catch (e, st) {
      KazumiLogger().e('同步失败', error: e, stackTrace: st);
      KazumiDialog.dismiss();
      KazumiDialog.showToast(message: '❌ 同步失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('樱花动漫账号'),
        // 右上角添加二维码图标
        actions: [
          IconButton(
            onPressed: _loggedIn ? _gotoGenerateQr : _gotoScan,
            icon: Icon(
              _loggedIn ? Icons.qr_code : Icons.qr_code_scanner,
              color: Colors.white,
            ),
            tooltip: _loggedIn ? '生成登录二维码' : '扫描二维码登录',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),
          Icon(Icons.person, size: 72, color: colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            _loggedIn ? '已登录 ✅' : '验证码登录',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (_loggedIn)
            Text(AuthService.getLocalToken() ?? '',
                style: TextStyle(fontSize: 11, color: colorScheme.outline)),
          const SizedBox(height: 32),

          if (!_loggedIn) ...[
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'QQ 邮箱',
                hintText: 'xxx@qq.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      hintText: '6位数字',
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _sending ? null : _sendCode,
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('发送'),
                ),
              ],
            ),

            if (_captchaChallenge != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _captchaController,
                decoration: InputDecoration(
                  labelText: '人机验证',
                  hintText: '请输入下方字符',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.verified_user),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _captchaChallenge!,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: colorScheme.primary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                maxLength: 6,
              ),
            ],

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _logging ? null : _login,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _logging
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('登录 / 注册', style: TextStyle(fontSize: 17)),
            ),
          ],

          if (_loggedIn) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.check_circle, size: 48, color: Colors.green),
                  SizedBox(height: 12),
                  Text('已登录', style: TextStyle(fontSize: 18)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 樱花同步按钮
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sync, size: 20),
                      SizedBox(width: 8),
                      Text('收藏同步', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '将追番列表同步到樱花服务器，双向合并',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _syncCollect,
                      icon: const Icon(Icons.sync),
                      label: Text(_syncing ? '同步中...' : '开始同步'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bangumi 绑定
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🎯 Bangumi 绑定',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (GStorage.getSetting(SettingsKeys.bangumiAccessToken)
                          .trim().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('已绑定',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.green.shade700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '绑定 Bangumi 后可同步追番列表和播放进度',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const _BangumiBindPage(),
                        ),
                      );
                    },
                    child: const Text('绑定 Bangumi'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 闲聊室
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChatRoomPage()),
                  );
                },
                icon: const Icon(Icons.chat),
                label: const Text('闲聊室（1金币/条）'),
              ),
            ),
            const SizedBox(height: 12),

            // 退出
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bangumi 绑定页面
class _BangumiBindPage extends StatefulWidget {
  const _BangumiBindPage();
  @override
  State<_BangumiBindPage> createState() => _BangumiBindPageState();
}

class _BangumiBindPageState extends State<_BangumiBindPage> {
  final _tokenController = TextEditingController();
  bool _binding = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _bind() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      KazumiDialog.showToast(message: '请输入 Bangumi Token');
      return;
    }
    setState(() => _binding = true);
    try {
      final res = await AuthService.bindBangumi(token);
      if (res['success'] == true) {
        await GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
        await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
        KazumiDialog.showToast(message: 'Bangumi 绑定成功 🎉');
        Navigator.of(context).pop();
      } else {
        KazumiDialog.showToast(message: res['error'] ?? '绑定失败');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '网络错误: $e');
    }
    setState(() => _binding = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasBangumi = GStorage.getSetting(SettingsKeys.bangumiAccessToken)
        .trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('绑定 Bangumi')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.link, size: 64),
          const SizedBox(height: 16),
          const Text('绑定 Bangumi 账号',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            hasBangumi ? '当前已绑定 Bangumi，可更新 Token' : '输入你的 Bangumi Access Token 完成绑定',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(
              labelText: 'Bangumi Access Token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _binding ? null : _bind,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: _binding
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('绑定'),
          ),
          if (hasBangumi) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                GStorage.putSetting(SettingsKeys.bangumiAccessToken, '');
                GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
                setState(() {});
                KazumiDialog.showToast(message: '已解除 Bangumi 绑定');
              },
              child: const Text('解除绑定', style: TextStyle(color: Colors.red)),
            ),
          ],
        ],
      ),
    );
  }
}
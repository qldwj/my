import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/plugins/animeko_converter.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/encoding.dart';

/// yhdmgz:// 深度链接处理服务
///
/// 当用户在浏览器中点击 yhdmgz://base64 链接时：
/// 1. Android 系统通过 Intent 将链接传给 App
/// 2. 该服务解析链接中的 Base64 编码的规则 JSON
/// 3. 自动导入/更新规则
class DeepLinkService {
  static const _channel = MethodChannel('com.predidit.kazumi/intent');

  DeepLinkService({required this.pluginsController});

  final PluginsController pluginsController;

  StreamSubscription<dynamic>? _intentSubscription;

  /// 初始化：检查启动时是否有等待处理的链接
  Future<void> init() async {
    try {
      // 检查启动 Intent 中是否包含链接
      final intentData = await _channel.invokeMethod<String>('checkIntent');
      if (intentData != null && intentData.isNotEmpty) {
        await _handleLink(intentData);
      }
    } catch (e) {
      KazumiLogger().w('DeepLink: check intent failed', error: e);
    }

    // 检查剪贴板中是否有 yhdmgz:// 链接
    try {
      // 延迟一下确保剪贴板服务就绪
      await Future.delayed(const Duration(milliseconds: 500));
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        final text = clipboardData.text!.trim();
        if (text.startsWith('yhdmgz://')) {
          KazumiLogger().i('DeepLink: 从剪贴板检测到规则链接');
          await _handleLink(text);
          // 清空剪贴板，避免重复导入
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      }
    } catch (e) {
      KazumiLogger().w('DeepLink: check clipboard failed', error: e);
    }

    // 监听应用运行时的新 Intent（onNewIntent）
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onIntent') {
        final url = call.arguments['url'] as String?;
        if (url != null && url.isNotEmpty) {
          await _handleLink(url);
        }
      }
    });
  }

  /// 处理 yhdmgz:// 链接（规则分享、番剧分享或 Bangumi 登录回调）
  Future<void> _handleLink(String url) async {
    KazumiLogger().i('DeepLink: 收到链接: $url');

    // 0️⃣ 番剧分享：yhdmgz://subject/<id>
    final subjectMatch = RegExp(r'^yhdmgz://subject/(\d+)').firstMatch(url);
    if (subjectMatch != null) {
      final subjectId = int.tryParse(subjectMatch.group(1) ?? '');
      if (subjectId != null) {
        // 通过 Modular 导航到番剧详情页
        try {
          // 使用 Modular 的导航
          final nav = _channel.binaryMessenger;
          // 简单的导航方式：使用 Navigator
          if (nav != null) {
            // 通过路由跳转到番剧详情
            // 这里需要一个 context，从 pluginsController 获取
          }
        } catch (_) {}
      }
      return;
    }

    // 🔄 扫码登录：yhdmgz://qrcode-login/<token>
    if (url.startsWith('yhdmgz://qrcode-login/')) {
      final token = url.replaceFirst('yhdmgz://qrcode-login/', '');
      if (token.isNotEmpty) {
        try {
          final client = HttpClient();
          final body = jsonEncode({'token': token, 'confirm': true});
          final request = await client.postUrl(
            Uri.parse('${AuthService.baseUrl}?action=qrcode_login'),
          );
          request.headers.set('Content-Type', 'application/json');
          request.write(body);
          final response = await request.close();
          final respBody = await response.transform(utf8.decoder).join();
          client.close();
          final data = jsonDecode(respBody) as Map<String, dynamic>;
          if (data['status'] == 'confirmed') {
            final userToken = data['token'] as String?;
            if (userToken != null && userToken.isNotEmpty) {
              AuthService.saveLocalToken(userToken);
              await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
            }
          }
        } catch (_) {}
      }
      return;
    }

    // 1️⃣ Bangumi OAuth 登录回调
    if (url.startsWith('yhdmgz://bangumi-auth')) {
      try {
        final uri = Uri.parse(url);
        final token = uri.queryParameters['token'];
        if (token != null && token.isNotEmpty) {
          await GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
          await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
          KazumiLogger().i('DeepLink: Bangumi OAuth 登录成功');
          _showToast('Bangumi 登录成功 🎉');
        } else {
          _showToast('Bangumi 登录失败：未获取到 Token');
        }
      } catch (e) {
        KazumiLogger().e('DeepLink: Bangumi OAuth 回调处理失败', error: e);
        _showToast('Bangumi 登录失败：${e.toString()}');
      }
      return;
    }

    // 2️⃣ 规则分享导入
    try {
      // 解析 Base64 → JSON
      final jsonStr = kazumiBase64ToJson(url);
      final data = jsonDecode(jsonStr);

      int count = 0;

      // 判断格式：单个 Plugin JSON 还是 Animeko 批量格式
      if (data is Map && data.containsKey('name') && data.containsKey('searchURL')) {
        // 单个 Kazumi Plugin 格式
        final plugin = Plugin.fromJson(Map<String, dynamic>.from(data));
        await pluginsController.updatePlugin(plugin);
        count = 1;
        KazumiLogger().i('DeepLink: 已导入规则: ${plugin.name}');
      } else if (data is Map || data is List) {
        // Animeko 批量格式
        final jsonStr2 = jsonEncode(data);
        final plugins = AnimekoRuleConverter.convertFromJson(jsonStr2);
        if (plugins.isEmpty) {
          KazumiLogger().w('DeepLink: 未找到可转换的规则');
          _showToast('未找到可转换的规则');
          return;
        }
        for (final plugin in plugins) {
          await pluginsController.updatePlugin(plugin);
          count++;
          KazumiLogger().i('DeepLink: 已导入规则: ${plugin.name}');
        }
      } else {
        KazumiLogger().w('DeepLink: 无法识别的规则格式');
        _showToast('无法识别的规则格式');
        return;
      }

      if (count > 0) {
        _showToast('成功导入 $count 条规则 🎉');
      }
    } catch (e, st) {
      KazumiLogger().e('DeepLink: 处理链接失败', error: e, stackTrace: st);
      _showToast('规则导入失败: ${e.toString()}');
    }
  }

  /// 显示 Toast 提示（安全地在主线程执行）
  void _showToast(String message) {
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        KazumiDialog.showToast(message: message);
      });
    } catch (_) {
      // 静默失败
    }
  }

  /// 释放资源
  void dispose() {
    _intentSubscription?.cancel();
    _channel.setMethodCallHandler(null);
  }
}

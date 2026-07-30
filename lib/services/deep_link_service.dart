import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';  // ✅ 新增
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/plugins/animeko_converter.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/encoding.dart';

/// yhdmgz:// 深度链接处理服务
///
/// 支持以下链接格式：
/// 1. yhdmgz://subject/552533 - 跳转到动漫详情页
/// 2. yhdmgz://bangumi-auth?token=xxx - Bangumi OAuth 登录回调
/// 3. yhdmgz://<base64> - 规则分享导入
class DeepLinkService {
  static const _channel = MethodChannel('com.predidit.kazumi/intent');

  DeepLinkService({required this.pluginsController});

  final PluginsController pluginsController;

  StreamSubscription<dynamic>? _intentSubscription;

  /// 初始化：检查启动时是否有等待处理的链接
  Future<void> init() async {
    try {
      final intentData = await _channel.invokeMethod<String>('checkIntent');
      if (intentData != null && intentData.isNotEmpty) {
        await _handleLink(intentData);
      }
    } catch (e) {
      KazumiLogger().w('DeepLink: check intent failed', error: e);
    }

    // 检查剪贴板中是否有 yhdmgz:// 链接
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        final text = clipboardData.text!.trim();
        if (text.startsWith('yhdmgz://')) {
          KazumiLogger().i('DeepLink: 从剪贴板检测到链接');
          await _handleLink(text);
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

  /// 处理 yhdmgz:// 链接
  Future<void> _handleLink(String url) async {
    KazumiLogger().i('DeepLink: 收到链接: $url');

    // ============================================================
    // 1️⃣ 处理 yhdmgz://subject/552533 格式（跳转到动漫详情页）
    // ============================================================
    if (url.startsWith('yhdmgz://subject/')) {
      try {
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments; // ['subject', '552533']

        if (pathSegments.length >= 2 && pathSegments[0] == 'subject') {
          final subjectId = int.tryParse(pathSegments[1]);
          if (subjectId != null) {
            KazumiLogger().i('DeepLink: 跳转到动漫详情，ID: $subjectId');
            _navigateToDetail(subjectId);
            return;
          } else {
            KazumiLogger().w('DeepLink: 无效的 subject ID: ${pathSegments[1]}');
            _showToast('无效的动漫ID');
            return;
          }
        }
      } catch (e) {
        KazumiLogger().e('DeepLink: 解析 subject 链接失败', error: e);
        _showToast('打开动漫详情失败');
        return;
      }
    }

    // ============================================================
    // 2️⃣ Bangumi OAuth 登录回调
    // ============================================================
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

    // ============================================================
    // 3️⃣ 规则分享导入
    // ============================================================
    try {
      final jsonStr = kazumiBase64ToJson(url);
      final data = jsonDecode(jsonStr);

      int count = 0;

      if (data is Map && data.containsKey('name') && data.containsKey('searchURL')) {
        final plugin = Plugin.fromJson(Map<String, dynamic>.from(data));
        await pluginsController.updatePlugin(plugin);
        count = 1;
        KazumiLogger().i('DeepLink: 已导入规则: ${plugin.name}');
      } else if (data is Map || data is List) {
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

  // ============================================================
  // ✅ 跳转到动漫详情页
  // ============================================================
  void _navigateToDetail(int subjectId) {
    try {
      // 使用工厂方法构建只有 ID 的 BangumiItem
      final bangumiItem = BangumiItem.withId(subjectId);

      // ✅ 使用 Modular 的导航方式
      Modular.to.pushNamed('/info/', arguments: bangumiItem);
      KazumiLogger().i('DeepLink: 已跳转到详情页，ID: $subjectId');
    } catch (e) {
      KazumiLogger().e('DeepLink: 跳转详情页失败', error: e);
      _showToast('打开详情页失败');
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
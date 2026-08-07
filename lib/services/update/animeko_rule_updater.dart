import 'dart:async';
import 'dart:convert';
import 'package:kazumi/plugins/animeko_converter.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Animeko 合集自动更新服务
///
/// 遍历已安装的合集，检查每个合集的更新时间，
/// 如果超过设置的间隔（默认30分钟）则自动从仓库拉取最新内容。
/// 计时器会持久化存储，杀掉后台再开继续倒计时。
class AnimekoRuleUpdater {
  static const _lastCheckKey = SettingsKeys.animekoRuleLastCheck;

  /// 获取用户设置的更新间隔（默认30分钟，范围1秒~60分钟）
  static Duration getUpdateInterval() {
    final minutes = GStorage.getSetting(SettingsKeys.animekoUpdateInterval);
    if (minutes <= 0) return const Duration(seconds: 1);
    if (minutes >= 60) return const Duration(minutes: 60);
    return Duration(minutes: minutes);
  }

  AnimekoRuleUpdater({required this.pluginsController});

  final PluginsController pluginsController;

  bool _isRunning = false;
  Timer? _timer;

  /// 初始化：启动时检查并开始计时
  Future<void> init() async {
    if (_isRunning) return;
    _isRunning = true;

    // 检查所有合集是否需要更新
    await _updateCollectionsIfNeeded();

    // 启动定时器，每分钟检查一次
    _timer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _updateCollectionsIfNeeded();
    });
  }

  /// 遍历所有合集，检查是否需要更新
  Future<void> _updateCollectionsIfNeeded() async {
    for (final plugin in pluginsController.pluginList) {
      if (plugin.isCollection && plugin.collectionUrl.isNotEmpty) {
        await _updateSingleCollection(plugin);
      }
    }
  }

  /// 更新单个合集
  Future<void> _updateSingleCollection(Plugin collection) async {
    try {
      final interval = getUpdateInterval();

      // 解析上次更新时间
      final lastUpdate = _parseTime(collection.collectionLastUpdate);
      if (lastUpdate != null) {
        final elapsed = DateTime.now().difference(lastUpdate);
        if (elapsed.inSeconds < interval.inSeconds) {
          // 还没到更新时间，显示下次更新时间
          final nextUpdate = lastUpdate.add(interval);
          collection.collectionNextUpdate = _formatTime(nextUpdate);
          return;
        }
      }

      KazumiLogger().i('AnimekoRuleUpdater: 更新合集: ${collection.name}');

      // 下载合集 JSON
      final json = await PluginSiteClient.instance.requestText(
        collection.collectionUrl,
        method: 'GET',
      );
      if (json.trim().isEmpty) return;

      // 转换
      final plugins = AnimekoRuleConverter.convertFromJson(json);
      if (plugins.isEmpty) return;

      // 更新子规则
      collection.childPlugins = plugins;
      final now = DateTime.now();
      collection.collectionLastUpdate = _formatTime(now);
      collection.collectionNextUpdate = _formatTime(now.add(interval));

      // 持久化
      await pluginsController.savePlugins();
      KazumiLogger().i('AnimekoRuleUpdater: 合集 ${collection.name} 更新完成，${plugins.length} 条规则');
    } catch (e) {
      KazumiLogger().w('AnimekoRuleUpdater: 合集 ${collection.name} 更新失败: $e');
    }
  }

  /// 解析时间字符串
  DateTime? _parseTime(String time) {
    try {
      return DateTime.parse(time);
    } catch (_) {
      // 兼容 "2024-01-01 12:00" 格式
      try {
        return DateTime.parse(time.replaceAll(' ', 'T'));
      } catch (_) {
        return null;
      }
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// 停止更新服务
  void dispose() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }
}

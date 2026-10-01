import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/date_time.dart';
import 'package:kazumi/utils/crypto.dart';
import 'package:kazumi/utils/version.dart';

/// 安装类型枚举
enum InstallationType {
  windowsMsix, // Kazumi_windows_1.7.5.msix
  windowsPortable, // Kazumi_windows_1.7.5.zip
  linuxDeb, // Kazumi_linux_1.7.5_amd64.deb
  linuxTar, // Kazumi_linux_1.7.5_amd64.tar.gz
  macosDmg, // Kazumi_macos_1.7.5.dmg
  androidApk, // Kazumi_android_1.7.5.apk
  ios, // iOS App
  unknown,
}

/// 更新信息类
class UpdateInfo {
  final String version;
  final String description;
  final String downloadUrl;
  final String releaseNotes;
  final String publishedAt;
  final InstallationType? installationType;
  final List<InstallationType> availableInstallationTypes;
  final List<dynamic> assets;

  UpdateInfo({
    required this.version,
    required this.description,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    this.installationType,
    this.availableInstallationTypes = const [],
    this.assets = const [],
  });

  /// 获取默认的安装类型（第一个可用类型）
  InstallationType get recommendedInstallationType {
    if (availableInstallationTypes.isNotEmpty) {
      return availableInstallationTypes.first;
    }
    return installationType ?? InstallationType.unknown;
  }

  /// 是否为测试版：版本号带 `-` 后缀（如 2.4.0-beta）即测试版，无后缀为正式版
  bool get isTestVersion => version.contains('-');
}

Map<String, dynamic>? getUpdateAssetForType(
    List<dynamic> assets, InstallationType type) {
  final patterns = getUpdateFilePatterns(type).map((p) => p.toLowerCase());

  try {
    final asset = assets.cast<Map<String, dynamic>>().firstWhere((asset) {
      final name = (asset['name'] as String?)?.toLowerCase() ?? '';
      return patterns.every((pattern) => name.contains(pattern));
    });
    return asset;
  } catch (_) {
    return null;
  }
}

String getUpdateDownloadUrlFromAsset(Map<String, dynamic>? asset) {
  if (asset == null) {
    return '';
  }
  final mirrorUrl = asset['mirror_download_url'] as String? ?? '';
  if (mirrorUrl.isNotEmpty) {
    return mirrorUrl;
  }
  return asset['browser_download_url'] as String? ?? '';
}

String getUpdateFileHashFromAsset(Map<String, dynamic> asset) {
  final digest = asset['digest'] as String? ?? '';
  if (digest.isNotEmpty && digest.startsWith('sha256:')) {
    return digest.substring(7);
  }
  return '';
}

/// 读取 GitHub release asset 的 size（字节）。缺失时返回 0。
int getUpdateFileSizeFromAsset(Map<String, dynamic>? asset) {
  if (asset == null) return 0;
  final s = asset['size'];
  if (s is int) return s;
  return int.tryParse(s?.toString() ?? '') ?? 0;
}

List<String> getUpdateFilePatterns(InstallationType installationType) {
  switch (installationType) {
    case InstallationType.windowsMsix:
      return ['windows', '.msix'];
    case InstallationType.windowsPortable:
      return ['windows', '.zip'];
    case InstallationType.macosDmg:
      return ['macos', '.dmg'];
    case InstallationType.androidApk:
      // 🆕 只要求 .apk 结尾：兼容正式版（YHDM_android_x.apk）
      // 和测试版（YHDM_beta_x.apk / 其它命名），避免因文件名不含 "android" 而匹配不到
      return ['.apk'];
    case InstallationType.linuxDeb:
    case InstallationType.linuxTar:
    case InstallationType.ios:
    case InstallationType.unknown:
      return [];
  }
}

class AutoUpdater {
  static final AutoUpdater _instance = AutoUpdater._internal();

  factory AutoUpdater() => _instance;

  AutoUpdater._internal();

  final DownloadHttpClient _downloadClient = DownloadHttpClient.instance;

  /// 检测所有可能的安装类型
  Future<List<InstallationType>> _detectAvailableInstallationTypes() async {
    List<InstallationType> availableTypes = [];

    try {
      if (Platform.isWindows) {
        // Windows 平台支持 MSIX 和 ZIP 便携版
        availableTypes.add(InstallationType.windowsMsix);
        availableTypes.add(InstallationType.windowsPortable);
      } else if (Platform.isLinux) {
        // Linux 平台支持 DEB 和 TAR.GZ
        availableTypes.add(InstallationType.linuxDeb);
        availableTypes.add(InstallationType.linuxTar);
      } else if (Platform.isMacOS) {
        // macOS 平台支持 DMG
        availableTypes.add(InstallationType.macosDmg);
      } else if (Platform.isIOS) {
        // iOS 平台通过 Github
        availableTypes.add(InstallationType.ios);
      } else if (Platform.isAndroid) {
        // Android 平台支持 APK
        availableTypes.add(InstallationType.androidApk);
      }
    } catch (e) {
      KazumiLogger().w('Update: detect installation types failed', error: e);
    }

    if (availableTypes.isEmpty) {
      availableTypes.add(InstallationType.unknown);
    }

    return availableTypes;
  }

  /// 检查是否有新版本可用
  /// [channel] 更新通道：'stable' 仅正式版；'beta'/'preview'/'both'/默认 → 全部版本（正式版+预览版）里挑最新
  Future<UpdateInfo?> checkForUpdates({String? channel}) async {
    try {
      // 渠道归一化：
      //   - 只有显式 'stable' 才走「仅正式版」（/releases/latest）
      //   - 'beta' 以及历史遗留值 'preview'、'both'、空值 一律走「全部版本挑最新」
      //     （'preview' 是更早版本的前端值；'both' 的旧分支「先查正式版、失败才查预览版」
      //       有个 bug：只要存在正式版就永远看不到更新的预览版，这里统一修正为 _latestBetaRelease）
      final String updateChannel =
          (channel ?? GStorage.getSetting(SettingsKeys.updateChannel) ?? 'beta')
              .toString();

      Map<String, dynamic> data;

      if (updateChannel == 'stable') {
        // 仅正式版
        data = await _latestRelease();
      } else {
        // 预览版/默认/兼容历史值：从全部版本（正式版 + 预览版）里挑版本号最高的
        data = await _latestBetaRelease();
      }

      if (!data.containsKey('tag_name')) {
        throw Exception('无效的响应数据');
      }

      final remoteVersion = data['tag_name'] as String;
      final currentVersion = ApiEndpoints.version;

      if (needUpdate(currentVersion, remoteVersion)) {
        final availableTypes = await _detectAvailableInstallationTypes();
        final isPrerelease = data['prerelease'] == true;

        return UpdateInfo(
          version: remoteVersion,
          description: (isPrerelease ? '🧪 测试版 ' : '') + (data['body'] ?? '发现新版本'),
          downloadUrl: '',
          releaseNotes: data['html_url'] ?? '',
          publishedAt: data['published_at'] ?? '',
          installationType: availableTypes.first,
          availableInstallationTypes: availableTypes,
          assets: data['assets'] ?? [],
        );
      }

      return null;
    } catch (e) {
      KazumiLogger().e('Update: check for updates failed', error: e);
      rethrow;
    }
  }

  /// 获取最新正式版
  Future<Map<String, dynamic>> _latestRelease() async {
    final raw = await _downloadClient.getPlain(ApiEndpoints.latestAppMirror);
    final data = json.decode(raw);
    if (data is! Map) {
      throw Exception('Invalid update response');
    }
    return Map<String, dynamic>.from(data);
  }

  /// 获取最新预览版（所有版本都有：正式版 + 测试版）
  /// 同时请求镜像与 GitHub，合并去重后挑选**版本号最高**的发布（不再只信镜像第一个，
  /// 避免镜像缓存滞后导致刚发布的测试版检测不到）。
  ///
  /// ⭐ 优化：镜像命中候选时**不再 await GitHub 直链**（国内 GitHub 5-10 秒，
  ///   之前每次都白等）。仅当镜像没拿到任何候选时才回落到 GitHub。
  Future<Map<String, dynamic>> _latestBetaRelease() async {
    final List<Map<String, dynamic>> candidates = [];
    // 按 tag 去重：镜像与 GitHub 是同一份数据源时只保留一份，避免重复项干扰排序
    final Set<String> seenTags = {};

    void addCandidate(dynamic item) {
      if (item is! Map) return;
      // 跳过草稿（未正式发布的 release）
      if (item['draft'] == true) return;
      if (item['assets'] is! List || (item['assets'] as List).isEmpty) return;
      final tag = item['tag_name'] as String?;
      if (tag == null || tag.isEmpty) return;
      if (!seenTags.add(tag)) return;
      candidates.add(Map<String, dynamic>.from(item));
    }

    // 1) 镜像（已替换 browser_download_url 为 gitcode 直链，国内快）
    try {
      final raw = await _downloadClient.getPlain(ApiEndpoints.allAppReleasesMirror);
      final list = json.decode(raw);
      if (list is List) {
        for (final item in list) {
          addCandidate(item);
        }
      }
    } catch (e) {
      KazumiLogger().w('Update: mirror for beta releases failed, fallback to GitHub', error: e);
    }

    // ⭐ 2) GitHub 兜底：仅在镜像没拿到任何候选时才打（之前是无脑 await 拖慢
    //   启动检查 5-10 秒）。镜像正常工作时直接走候选挑选，跳过 GitHub。
    if (candidates.isEmpty) {
      try {
        final raw = await _downloadClient.getPlain(ApiEndpoints.allAppReleases);
        final list = json.decode(raw);
        if (list is List) {
          for (final item in list) {
            addCandidate(item);
          }
        }
      } catch (e) {
        KazumiLogger().w('Update: github releases for beta failed', error: e);
      }
    }

    if (candidates.isEmpty) {
      // 全部失败 → 回退到正式版
      return _latestRelease();
    }

    // 3) 挑出版本号最高的（needUpdate：b 比 a 新 → b 排前面）
    candidates.sort((a, b) {
      final ta = (a['tag_name'] as String?) ?? '';
      final tb = (b['tag_name'] as String?) ?? '';
      if (needUpdate(ta, tb)) return 1; // tb 比 ta 新 → b 在前
      if (needUpdate(tb, ta)) return -1; // ta 比 tb 新 → a 在前
      return 0;
    });
    return candidates.first;
  }

  /// 自动检查更新（只在启用自动更新时）
  ///
  /// 行为：**每次启动都打 GitHub**（不做时间节流），保证你升级到新版
  /// 后第一次启动一定能看到下一个版本提示。手点「设置→关于→检查更新」
  /// 走 [manualCheckForUpdates]，与这里并行。
  ///
  /// 通道（[SettingsKeys.updateChannel]）：
  ///  - 'stable' → 仅看正式版
  ///  - 其他/默认 → 正式版 + 测试版一起挑版本号最高的（[checkForUpdates]
  ///    内部 [_latestBetaRelease] 拉的是 GitHub 全部 release，**两种都包含**）
  ///
  /// 保留的保护：
  ///  - 同版本静默下载连续失败 ≥3 次 → 本日不再无脑重试（避免坏包死循环）
  ///  - 本机版本号变化 → 清掉失败计数（升级后从干净状态开始）
  ///
  /// 调用约定：**checkPendingUpdate() 由本方法全权负责**，外部（如
  /// MyController.checkUpdate）不要再重复调用，否则会双弹"立即安装"。
  Future<void> autoCheckForUpdates() async {
    try {
      await Future.delayed(const Duration(seconds: 3));

      final autoUpdate = GStorage.getSetting(SettingsKeys.autoUpdate);
      if (autoUpdate != true) {
        KazumiLogger().i('Update: auto update not enabled, skipping GitHub');
        // ⭐ 即便关掉了自动检查，上次"已下载完但用户没装"的 pending 仍然要
        //   提示安装——这条之前会漏（早 return 后 my_controller 又没调），
        //   表现就是"上次明明下完了下次进 App 不提示"。
        await checkPendingUpdate();
        return;
      }

      // ⭐ 升级感知：本机版本号变化（首次安装 / 升级到新版 / 回滚）→
      //   清掉同版本失败计数，保证刚升上的版本不被旧失败"连坐"。
      final currentVersion = ApiEndpoints.version;
      final lastSeenVersion =
          GStorage.getSetting(SettingsKeys.lastCheckedCurrentVersion);
      if (lastSeenVersion != currentVersion) {
        KazumiLogger().i(
          'Update: 本机版本号变化 ($lastSeenVersion → $currentVersion)，'
          '重置同版本失败计数',
        );
        await GStorage.putSetting(
            SettingsKeys.silentDownloadFailVersion, '');
        await GStorage.putSetting(SettingsKeys.silentDownloadFailCount, 0);
        await GStorage.putSetting(
            SettingsKeys.lastCheckedCurrentVersion, currentVersion);
      }

      KazumiLogger().i('Update: auto checking for updates...');
      final updateInfo = await checkForUpdates();
      if (updateInfo == null) {
        KazumiLogger().i('Update: already up to date (current=$currentVersion)');
        // 没有新版时仍要处理"上次完整下载好但用户没装的 pending"
        await checkPendingUpdate();
        return;
      }

      KazumiLogger().i(
        'Update: 发现新版 ${updateInfo.version} '
        '(${updateInfo.isTestVersion ? '测试版' : '正式版'})，current=$currentVersion',
      );

      final silentDownload =
          GStorage.getSetting(SettingsKeys.silentDownload);
      bool willSilentDownload = false;
      if (silentDownload == true && Platform.isAndroid) {
        // ⭐ 同版本连续失败 ≥3 次：本日不再无脑重试，避免反复
        //   「半截 APK → 立即安装 → 安装包无效」死循环。
        final failVer =
            GStorage.getSetting(SettingsKeys.silentDownloadFailVersion);
        final failCnt =
            GStorage.getSetting(SettingsKeys.silentDownloadFailCount);
        if (failVer == updateInfo.version && failCnt >= 3) {
          KazumiLogger().w(
            'Update: ${updateInfo.version} 已连续 $failCnt 次静默下载失败，'
            '本次跳过自动重试（用户可在「设置→关于」手动更新）',
          );
        } else {
          willSilentDownload = true;
          // 后台下载 APK，下次启动看到「立即安装」时多半已下完
          unawaited(_silentDownloadApk(updateInfo));
        }
      }

      // ⭐ **始终弹窗**：旧逻辑只在 silentDownload=false 时弹，于是
      //   默认配置下用户首次进入 App 只看到后台下载、没有任何提示，
      //   误以为"检测不工作、必须手动检查"。现在：发现新版必弹；
      //   并行后台下载只是给后续「立即安装」做加速，不再吞掉对话框。
      _showUpdateDialog(updateInfo,
          isAutoCheck: true, silentDownloading: willSilentDownload);
    } catch (e) {
      KazumiLogger().w('Update: auto check for updates failed', error: e);
    }
  }

  /// 静默下载APK（后台下载，不弹窗）
  Future<void> _silentDownloadApk(UpdateInfo updateInfo) async {
    try {
      final asset = getUpdateAssetForType(updateInfo.assets, InstallationType.androidApk);
      final downloadUrl = getUpdateDownloadUrlFromAsset(asset);
      if (downloadUrl.isEmpty) {
        // 找不到可下载包时必须回退成弹窗，否则「静默模式」下永远没有任何提示
        _showUpdateDialog(updateInfo, isAutoCheck: true);
        return;
      }

      final expectedHash = getUpdateFileHashFromAsset(asset ?? const {});
      final expectedSize = getUpdateFileSizeFromAsset(asset);
      final fileName = 'Kazumi-${updateInfo.version}.apk';
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);

      // ⭐ 已存在的文件**必须**做完整性校验。
      //   旧逻辑只看 file.exists()，于是「上次下到一半 / 进程被杀 / 网络中断」
      //   留下的半个 APK 会被当成"已下载完成"→ 写 pending → 下次启动
      //   弹「立即安装」→ 包安装器报「安装包无效」。这正是用户反馈的现象。
      if (await file.exists()) {
        final sane = await _isApkFileSane(file, expectedHash, expectedSize);
        if (sane) {
          KazumiLogger().i('Update: APK 已完整存在，写 pending: $filePath');
          await GStorage.putSetting(
              SettingsKeys.pendingUpdateVersion, updateInfo.version);
          await GStorage.putSetting(
              SettingsKeys.pendingUpdatePath, filePath);
          return;
        }
        KazumiLogger().w(
          'Update: 本机 $fileName 完整性校验未通过（半截/损坏/0 字节），删除并重下',
        );
        try {
          await file.delete();
        } catch (_) {}
      }

      // ⭐ 原子下载：先下到 *.part，下载完校验通过再 rename 到正式名。
      //   任何中断都只会在 *.part 上留下半截文件，正式路径不会出现
      //   "存在但不完整"的状态。
      final partFile = File('$filePath.part');
      try {
        if (await partFile.exists()) await partFile.delete();
      } catch (_) {}

      KazumiLogger().i('Update: silent download started: $downloadUrl');
      await _downloadClient.download(downloadUrl, partFile.path);

      final sane =
          await _isApkFileSane(partFile, expectedHash, expectedSize);
      if (!sane) {
        KazumiLogger().w(
          'Update: silent download 完整性未通过，丢弃（不写 pending，下次重试）：$filePath',
        );
        try {
          await partFile.delete();
        } catch (_) {}
        await _recordSilentDownloadFailure(updateInfo.version);
        return;
      }
      await partFile.rename(filePath);
      KazumiLogger().i('Update: silent download completed: $filePath');

      await GStorage.putSetting(
          SettingsKeys.pendingUpdateVersion, updateInfo.version);
      await GStorage.putSetting(
          SettingsKeys.pendingUpdatePath, filePath);
      // ⭐ 下载成功，清掉该版本失败计数
      await GStorage.putSetting(
          SettingsKeys.silentDownloadFailVersion, '');
      await GStorage.putSetting(SettingsKeys.silentDownloadFailCount, 0);
    } catch (e) {
      KazumiLogger().w('Update: silent download failed', error: e);
      // ⭐ 累计同版本失败次数；autoCheckForUpdates 据此决定是否继续重试。
      await _recordSilentDownloadFailure(updateInfo.version);
      // 静默下载失败不能静吞，否则用户等不到更新提示
      _showUpdateDialog(updateInfo, isAutoCheck: true);
    }
  }

  /// 累计同版本的静默下载失败计数（达到 3 次后 auto check 会自动跳过该版本）
  Future<void> _recordSilentDownloadFailure(String version) async {
    try {
      final prevVer =
          GStorage.getSetting(SettingsKeys.silentDownloadFailVersion);
      final prevCnt =
          GStorage.getSetting(SettingsKeys.silentDownloadFailCount);
      final newCnt = prevVer == version ? prevCnt + 1 : 1;
      await GStorage.putSetting(
          SettingsKeys.silentDownloadFailVersion, version);
      await GStorage.putSetting(
          SettingsKeys.silentDownloadFailCount, newCnt);
      KazumiLogger().w('Update: 静默下载失败 第 $newCnt 次 版本=$version');
    } catch (_) {}
  }

  /// APK 完整性校验：
  ///  - 有 sha256（GitHub release asset.digest）→ 必须严格匹配；
  ///  - 没 sha256 但有 size → 必须严格匹配；
  ///  - 都没有 → 兜底要求 > 5MB（避免 0 字节 / 网络异常留下的半截文件
  ///    被错判为可用）。
  Future<bool> _isApkFileSane(
      File file, String expectedHash, int expectedSize) async {
    try {
      if (!await file.exists()) return false;
      final len = await file.length();
      if (len <= 0) return false;
      if (expectedHash.isNotEmpty) {
        final actual = await calculateFileHash(file);
        final ok = actual.toLowerCase() == expectedHash.toLowerCase();
        if (!ok) {
          KazumiLogger().w(
            'Update: APK hash 不匹配 期望=$expectedHash 实际=$actual',
          );
        }
        return ok;
      }
      if (expectedSize > 0) {
        final ok = len == expectedSize;
        if (!ok) {
          KazumiLogger().w(
            'Update: APK size 不匹配 期望=$expectedSize 实际=$len',
          );
        }
        return ok;
      }
      return len > 5 * 1024 * 1024;
    } catch (e) {
      KazumiLogger().w('Update: APK 完整性校验异常', error: e);
      return false;
    }
  }

  /// 启动时检查是否有待安装的更新
  Future<void> checkPendingUpdate() async {
    try {
      final pendingVersion = GStorage.getSetting(SettingsKeys.pendingUpdateVersion);
      final pendingPath = GStorage.getSetting(SettingsKeys.pendingUpdatePath);
      if (pendingVersion == null || pendingVersion.isEmpty) return;
      if (pendingPath == null || pendingPath.isEmpty) return;

      final file = File(pendingPath);
      if (!await file.exists()) {
        GStorage.putSetting(SettingsKeys.pendingUpdateVersion, '');
        GStorage.putSetting(SettingsKeys.pendingUpdatePath, '');
        return;
      }
      // ⭐ 兜底：pending 指向的 apk 必须 > 1MB 且可读，避免上次留半个 / 0 字节
      //   的文件再次进入"立即安装"循环。
      try {
        final len = await file.length();
        if (len < 1024 * 1024) {
          KazumiLogger().w(
            'Update: pending APK 文件尺寸过小 ($len B)，判定损坏，清掉 pending: $pendingPath',
          );
          GStorage.putSetting(SettingsKeys.pendingUpdateVersion, '');
          GStorage.putSetting(SettingsKeys.pendingUpdatePath, '');
          try {
            await file.delete();
          } catch (_) {}
          return;
        }
      } catch (e) {
        KazumiLogger().w('Update: pending APK 读取失败，清掉 pending', error: e);
        GStorage.putSetting(SettingsKeys.pendingUpdateVersion, '');
        GStorage.putSetting(SettingsKeys.pendingUpdatePath, '');
        return;
      }

      final currentVersion = ApiEndpoints.version;
      if (needUpdate(currentVersion, pendingVersion)) {
        _showPendingUpdateDialog(pendingVersion, pendingPath);
      } else {
        // 版本相同，清理
        GStorage.putSetting(SettingsKeys.pendingUpdateVersion, '');
        GStorage.putSetting(SettingsKeys.pendingUpdatePath, '');
      }
    } catch (e) {
      KazumiLogger().w('Update: check pending update failed', error: e);
    }
  }

  /// 显示待安装更新对话框
  void _showPendingUpdateDialog(String version, String filePath) {
    KazumiDialog.show(
      builder: (context) => AlertDialog(
        title: Text('新版本 $version 已下载完成'),
        content: const Text('是否立即安装？'),
        actions: [
          TextButton(
            onPressed: () {
              GStorage.putSetting(SettingsKeys.pendingUpdateVersion, '');
              GStorage.putSetting(SettingsKeys.pendingUpdatePath, '');
              KazumiDialog.dismiss();
            },
            child: const Text('稍后安装'),
          ),
          FilledButton(
            onPressed: () {
              KazumiDialog.dismiss();
              _installUpdate(filePath, InstallationType.androidApk);
            },
            child: const Text('立即安装'),
          ),
        ],
      ),
    );
  }

  /// 手动检查更新
  Future<void> manualCheckForUpdates() async {
    // ⭐ in-flight 锁：用户在「设置→关于」连点 5 次"检查更新"只会真正打
    //   GitHub 一次（其余复用同一个 Future），避免撞 GitHub API 限流。
    final inflight = _manualCheckInFlight;
    if (inflight != null) {
      KazumiLogger().i('Update: 已在检查中，复用 in-flight future');
      return inflight;
    }
    final f = _doManualCheck();
    _manualCheckInFlight = f;
    try {
      await f;
    } finally {
      _manualCheckInFlight = null;
    }
  }

  Future<void>? _manualCheckInFlight;

  Future<void> _doManualCheck() async {
    try {
      final updateInfo = await checkForUpdates();
      if (updateInfo != null) {
        _showUpdateDialog(updateInfo, isAutoCheck: false);
      } else {
        KazumiDialog.showToast(message: '当前已经是最新版本！');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '检查更新失败');
    }
  }

  /// 显示更新对话框
  /// [silentDownloading]=true 时附带一行"已在后台下载 vX 安装包"提示，
  /// 这样自动检查路径也能弹窗告知用户，不再像以前那样静默吞掉。
  void _showUpdateDialog(UpdateInfo updateInfo,
      {bool isAutoCheck = false, bool silentDownloading = false}) {
    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text('发现新版本 ${updateInfo.version}'),
              ),
              const SizedBox(width: 8),
              // 右上角角标：正式版 / 测试版（按版本号是否带 -后缀判断）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: updateInfo.isTestVersion
                      ? const Color(0xFFFFF3E0)
                      : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  updateInfo.isTestVersion ? '🧪 测试版' : '正式版',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: updateInfo.isTestVersion
                        ? const Color(0xFFE65100)
                        : const Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(updateInfo.description),
                // ⭐ 自动检查 + 静默下载并行时的提示：用户既能立即看到
                //   "有新版"，又知道后台已经在帮他下，下次启动会弹"立即安装"。
                if (silentDownloading) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.cloud_download_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '已同时在后台下载 ${updateInfo.version} 安装包，'
                          '下次进入 App 会自动提示安装；也可在此处点"立即下载"立刻获取。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                if (updateInfo.publishedAt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '发布时间: ${formatDate(updateInfo.publishedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                if (!Platform.isLinux && !Platform.isIOS) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择安装类型:',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 8),
                        ...updateInfo.availableInstallationTypes.map((type) {
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () {
                                  KazumiDialog.dismiss();
                                  _downloadUpdateWithType(updateInfo, type);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withValues(alpha: 0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.download,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _getInstallationTypeDescription(type),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (isAutoCheck)
              TextButton(
                onPressed: () {
                  GStorage.putSetting(SettingsKeys.autoUpdate, false);
                  KazumiDialog.dismiss();
                  KazumiDialog.showToast(message: '已关闭自动更新');
                },
                child: Text(
                  '关闭自动更新',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: Text(
                '稍后提醒',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            if (updateInfo.releaseNotes.isNotEmpty)
              TextButton(
                onPressed: () {
                  launchUrl(Uri.parse(updateInfo.releaseNotes),
                      mode: LaunchMode.externalApplication);
                },
                child: const Text('查看详情'),
              ),
            TextButton(
              onPressed: () {
                KazumiDialog.dismiss();
                // 直接使用第一个可用的安装类型
                if (updateInfo.availableInstallationTypes.isNotEmpty) {
                  _downloadUpdateWithType(
                      updateInfo, updateInfo.availableInstallationTypes.first);
                }
              },
              child: const Text('立即更新'),
            ),
          ],
        );
      },
    );
  }

  /// 获取安装类型的描述
  String _getInstallationTypeDescription(InstallationType type) {
    switch (type) {
      case InstallationType.windowsMsix:
        return 'Windows MSIX 包';
      case InstallationType.windowsPortable:
        return 'Windows 便携版 (ZIP)';
      case InstallationType.linuxDeb:
        return 'Linux DEB 包';
      case InstallationType.linuxTar:
        return 'Linux TAR 包';
      case InstallationType.macosDmg:
        return 'macOS DMG 镜像';
      case InstallationType.androidApk:
        return 'Android APK';
      case InstallationType.ios:
        return 'iOS ipa';
      case InstallationType.unknown:
        return '未知安装类型';
    }
  }

  /// 根据选择的类型下载更新
  Future<void> _downloadUpdateWithType(
      UpdateInfo updateInfo, InstallationType selectedType) async {
    try {
      // iOS 和 Linux 直接跳转到 Release 页面
      if (selectedType == InstallationType.ios ||
          selectedType == InstallationType.linuxDeb ||
          selectedType == InstallationType.linuxTar) {
        String releaseUrl = updateInfo.releaseNotes;
        if (releaseUrl.isEmpty) {
          releaseUrl = ApiEndpoints.latestApp;
        }
        launchUrl(Uri.parse(releaseUrl), mode: LaunchMode.externalApplication);
        return;
      }

      final asset = getUpdateAssetForType(updateInfo.assets, selectedType);
      final downloadUrl = getUpdateDownloadUrlFromAsset(asset);
      if (asset == null || downloadUrl.isEmpty) {
        KazumiDialog.showToast(
            message:
                '没有找到 ${_getInstallationTypeDescription(selectedType)} 的下载链接');
        return;
      }

      final expectedHash = getUpdateFileHashFromAsset(asset);

      // 创建一个临时的 UpdateInfo 对象用于下载
      final downloadInfo = UpdateInfo(
        version: updateInfo.version,
        description: updateInfo.description,
        downloadUrl: downloadUrl,
        releaseNotes: updateInfo.releaseNotes,
        publishedAt: updateInfo.publishedAt,
        installationType: selectedType,
        availableInstallationTypes: [selectedType],
        assets: updateInfo.assets,
      );

      _downloadUpdate(downloadInfo, expectedHash);
    } catch (e) {
      KazumiDialog.showToast(message: '下载失败: ${e.toString()}');
      KazumiLogger().e('Update: download update failed', error: e);
    }
  }

  /// 下载更新
  Future<void> _downloadUpdate(
      UpdateInfo updateInfo, String expectedHash) async {
    if (updateInfo.downloadUrl.isEmpty) {
      KazumiDialog.showToast(message: '没有找到合适的下载链接');
      return;
    }

    // 显示下载进度对话框
    DateTime? _lastTime;
    int _lastBytes = 0;

    KazumiDialog.show(
      clickMaskDismiss: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('正在下载更新'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<(int, int)>(
                valueListenable: _downloadBytes,
                builder: (context, bytes, child) {
                  final received = bytes.$1;
                  final total = bytes.$2;
                  final value = total > 0 ? received / total : 0.0;

                  // 🆕 用真实字节数计算速度与剩余时间（不再用百分比×50MB 估算）
                  final now = DateTime.now();
                  double speed = 0; // bytes/s
                  Duration? eta;
                  if (_lastTime != null) {
                    final elapsedMs =
                        now.difference(_lastTime!).inMilliseconds;
                    final deltaBytes = received - _lastBytes;
                    // 至少 300ms 采样一次，避免抖动导致速度虚高
                    if (elapsedMs >= 300 && deltaBytes >= 0) {
                      speed = deltaBytes / (elapsedMs / 1000);
                      if (speed > 1024 && total > received) {
                        eta = Duration(
                            seconds: ((total - received) / speed).round());
                      }
                      _lastTime = now;
                      _lastBytes = received;
                    }
                  } else {
                    _lastTime = now;
                    _lastBytes = received;
                  }

                  return Column(
                    children: [
                      LinearProgressIndicator(value: value),
                      const SizedBox(height: 8),
                      Text('${(value * 100).toStringAsFixed(1)}%'
                          '${total > 0 ? '  (${_fmtSize(received)} / ${_fmtSize(total)})' : ''}'),
                      if (speed > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '速度: ${_fmtSpeed(speed)}'
                          '${eta != null ? '   剩余: ${_fmtEta(eta)}' : ''}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _cancelDownload();
                KazumiDialog.dismiss();
              },
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    try {
      final downloadPath = await _downloadFile(
          updateInfo.downloadUrl, updateInfo.version, expectedHash);

      // 不自动关闭对话框，而是显示下载完成状态
      _showDownloadCompleteDialog(downloadPath, updateInfo);
    } catch (e) {
      KazumiDialog.dismiss();

      // 显示详细的错误信息
      String errorMessage = '下载失败';
      if (e.toString().contains('Permission denied') ||
          e.toString().contains('Operation not permitted')) {
        errorMessage = '权限不足，文件已保存到应用临时目录';
      } else if (e.toString().contains('No space left')) {
        errorMessage = '磁盘空间不足';
      } else if (e.toString().contains('Network')) {
        errorMessage = '网络连接错误';
      } else if (e.toString().contains('文件完整性验证失败')) {
        errorMessage = '文件完整性验证失败，可能是网络传输错误';
      }

      KazumiDialog.show(
        builder: (context) {
          return AlertDialog(
            title: const Text('下载失败'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorMessage),
                const SizedBox(height: 8),
                Text(
                  '错误详情: ${e.toString()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => KazumiDialog.dismiss(),
                child: const Text('确定'),
              ),
              TextButton(
                onPressed: () {
                  KazumiDialog.dismiss();
                  // 重新尝试下载
                  _downloadUpdate(updateInfo, expectedHash);
                },
                child: const Text('重试'),
              ),
            ],
          );
        },
      );

      KazumiLogger().e('Update: download update failed', error: e);
    }
  }

  final ValueNotifier<double> _downloadProgress = ValueNotifier(0.0);
  /// 🆕 真实下载字节进度（received, total），用于准确计算速度/剩余时间
  final ValueNotifier<(int, int)> _downloadBytes = ValueNotifier((0, 0));

  /// 字节 → 人类可读（KB/MB/GB）
  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
  }

  /// 速度 → 人类可读（KB/s、MB/s）
  static String _fmtSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)}B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(0)}KB/s';
    }
    return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(1)}MB/s';
  }

  /// 剩余时间 → 「1分23秒」/「12秒」
  static String _fmtEta(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}秒';
    if (d.inMinutes < 60) {
      return '${d.inMinutes}分${d.inSeconds.remainder(60)}秒';
    }
    return '${d.inHours}时${d.inMinutes.remainder(60)}分';
  }
  CancelToken? _cancelToken;

  void _cancelDownload() {
    _cancelToken?.cancel();
  }

  /// 显示下载完成对话框
  void _showDownloadCompleteDialog(String filePath, UpdateInfo updateInfo) {
    // 替换当前的下载进度对话框内容
    KazumiDialog.dismiss();

    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          title: const Text('下载完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('新版本 ${updateInfo.version} 已下载完成'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '安装过程中应用将会退出',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '文件位置:',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      filePath,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: Text(
                '稍后安装',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            // 🆕 Android：用其他应用打开（MT管理器、NP管理器等）
            if (Platform.isAndroid)
              TextButton(
                onPressed: () {
                  KazumiDialog.dismiss();
                  _openWithFileManager(filePath);
                },
                child: const Text('用其他应用打开'),
              ),
            if (isDesktop())
              TextButton(
                onPressed: () {
                  // 在文件管理器中显示文件
                  _revealInFileManager(filePath);
                },
                child: Text('打开文件夹'),
              ),
            TextButton(
              onPressed: () {
                KazumiDialog.dismiss();
                _installUpdate(
                    filePath, updateInfo.recommendedInstallationType);
              },
              child: const Text('立即安装'),
            ),
          ],
        );
      },
    );
  }

  /// 🆕 Android：用第三方文件管理器（MT管理器/NP管理器等）打开 APK 文件
  void _openWithFileManager(String filePath) async {
    try {
      if (!Platform.isAndroid) return;

      final file = File(filePath);
      if (!await file.exists()) {
        KazumiDialog.showToast(message: '文件不存在');
        return;
      }

      // 使用 OpenFilex 打开 APK 文件
      // Android 系统会弹出"打开方式"选择器
      // 用户可以选择 MT 管理器、NP 管理器等文件管理器
      // 这些管理器打开后会直接定位到该 APK 文件所在目录
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        // 如果直接打开文件失败，尝试打开其所在目录
        final dirPath = file.parent.path;
        final dirResult = await OpenFilex.open(dirPath);
        if (dirResult.type != ResultType.done) {
          KazumiDialog.showToast(
              message: '无法打开文件，请手动前往目录: ${file.parent.path}');
        }
      }
    } catch (e) {
      KazumiLogger().e('Update: open with file manager failed', error: e);
    }
  }

  /// 下载文件
  Future<String> _downloadFile(
      String url, String version, String expectedHash) async {
    final fileName = _getFileNameFromUrl(url, version);

    // 统一使用临时目录
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/$fileName';
    final file = File(filePath);

    // 检查文件是否已存在
    if (await file.exists()) {
      try {
        //使用哈希验证文件完整性
        final localHash = await calculateFileHash(file);
        if (localHash == expectedHash) {
          // 文件已存在且哈希匹配，直接返回
          KazumiLogger().i(
              'Update: file already exists and hash verified, skipping download: $filePath');
          _downloadProgress.value = 1.0;
          return filePath;
        } else {
          // 文件存在但哈希不匹配，删除后重新下载
          KazumiLogger().i(
              'Update: file hash mismatch detected (local: $localHash, expected: $expectedHash), deleting and re-downloading');
          await file.delete();
        }
      } catch (e) {
        // 验证过程中出错，删除文件重新下载
        KazumiLogger().w(
            'Update: file verification failed, deleting and re-downloading',
            error: e);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    _cancelToken = CancelToken();

    await _downloadClient.download(
      url,
      filePath,
      cancelToken: _cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          _downloadProgress.value = received / total;
          _downloadBytes.value = (received, total);
        }
      },
    );

    // 下载完成后验证文件哈希
    final downloadedHash = await calculateFileHash(file);
    if (downloadedHash != expectedHash) {
      // 哈希不匹配，删除文件并抛出异常
      await file.delete();
      throw Exception('文件完整性验证失败: 期望 $expectedHash，实际 $downloadedHash');
    }
    KazumiLogger().i('Update: file downloaded and hash verified: $filePath');

    return filePath;
  }

  /// 安装更新
  void _installUpdate(
      String filePath, InstallationType installationType) async {
    try {
      // 显示准备退出的提示
      KazumiDialog.showToast(message: '准备安装更新，应用即将退出...');

      await Future.delayed(const Duration(seconds: 2));

      if (Platform.isWindows) {
        if (installationType == InstallationType.windowsMsix) {
          final Uri fileUri = Uri.file(filePath);
          if (await canLaunchUrl(fileUri)) {
            await launchUrl(fileUri);
          } else {
            throw 'Could not launch $fileUri';
          }
        } else {
          await Process.start('explorer.exe', [filePath], runInShell: true);
        }
        await Future.delayed(const Duration(seconds: 1));
        exit(0);
      } else if (Platform.isMacOS) {
        if (filePath.endsWith('.dmg')) {
          await Process.start('open', [filePath]);
          exit(0);
        }
      } else if (Platform.isAndroid) {
        // ⭐ 安装前最后一道校验：存在 + 可读 + >1MB，避免系统包安装器
        //   抛"安装包无效"后再回头处理。
        final f = File(filePath);
        int len = 0;
        try {
          if (await f.exists()) len = await f.length();
        } catch (_) {}
        if (len < 1024 * 1024) {
          KazumiDialog.showToast(
              message: '安装包已损坏或不完整，请在「设置→关于」重新检查更新');
          GStorage.putSetting(SettingsKeys.pendingUpdateVersion, '');
          GStorage.putSetting(SettingsKeys.pendingUpdatePath, '');
          try {
            if (len > 0) await f.delete();
          } catch (_) {}
          return;
        }
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          KazumiDialog.showToast(message: '无法打开安装文件: ${result.message}');
          return;
        }
      }
    } catch (e) {
      KazumiDialog.showToast(message: '启动安装程序失败: ${e.toString()}');
      KazumiLogger().e('Update: launch installer failed', error: e);
    }
  }

  /// 在文件管理器中显示文件
  void _revealInFileManager(String filePath) async {
    try {
      final type = await FileSystemEntity.type(filePath);
      String targetDirOrFile;

      // 如果传入的本来就是目录则打开这个目录
      // 如果是文件则打开包含它的目录
      if (type == FileSystemEntityType.notFound) {
        KazumiDialog.showToast(message: '文件或目录不存在');
        return;
      } else if (type == FileSystemEntityType.directory) {
        targetDirOrFile = filePath;
      } else {
        targetDirOrFile = File(filePath).parent.path;
      }

      if (Platform.isWindows) {
        if (type == FileSystemEntityType.file) {
          final arg = '/select,${filePath.replaceAll('/', r'\')}';
          await Process.start('explorer.exe', [arg], runInShell: true);
        } else {
          await Process.start(
              'explorer.exe', [targetDirOrFile.replaceAll('/', r'\')],
              runInShell: true);
        }
      } else if (Platform.isMacOS) {
        if (type == FileSystemEntityType.file) {
          await Process.start('open', ['-R', filePath]);
        } else {
          await Process.start('open', [targetDirOrFile]);
        }
      } else if (Platform.isLinux) {
        // 尝试打开包含文件的文件夹
        await Process.start('xdg-open', [targetDirOrFile]);
      } else {
        KazumiDialog.showToast(message: '此平台不支持通过此方法打开文件管理器');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '无法打开文件管理器');
      KazumiLogger().w('Update: reveal in file manager failed', error: e);
    } finally {
      try {
        // 确保对话框被关闭
        KazumiDialog.dismiss();
      } catch (_) {}
    }
  }

  /// 从URL获取文件名
  String _getFileNameFromUrl(String url, String version) {
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.last;

    if (fileName.isNotEmpty) {
      return fileName;
    }

    // 回退方案
    String extension = '';
    if (Platform.isWindows) {
      extension = '.msix';
    } else if (Platform.isMacOS) {
      extension = '.dmg';
    } else if (Platform.isLinux) {
      extension = '.deb';
    } else if (Platform.isAndroid) {
      extension = '.apk';
    }
    return 'Kazumi-$version$extension';
  }
}
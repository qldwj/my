import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/bean/dialog/dialog_helper.dart';
import 'package:yhdm/l10n/app_localizations.dart';
import 'package:yhdm/services/platform/secure_bookmark_service.dart';
import 'package:yhdm/services/storage/storage.dart';
import 'package:yhdm/utils/file_system.dart';
import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  late int parallelEpisodes;
  late int parallelSegments;
  late bool downloadDanmaku;
  late bool downloadNotify;
  late bool downloadWifiOnly;
  String downloadDirectory = '';
  String defaultDownloadDirectory = '';
  bool isSelectingDirectory = false;

  @override
  void initState() {
    super.initState();
    parallelEpisodes =
        GStorage.getSetting(SettingsKeys.downloadParallelEpisodes);
    parallelSegments =
        GStorage.getSetting(SettingsKeys.downloadParallelSegments);
    downloadDanmaku = GStorage.getSetting(SettingsKeys.downloadDanmaku);
    downloadNotify = GStorage.getSetting(SettingsKeys.downloadCompleteNotify);
    downloadWifiOnly = GStorage.getSetting(SettingsKeys.downloadWifiOnly);
    downloadDirectory =
        GStorage.getSetting(SettingsKeys.downloadDirectory).trim();
    _loadDefaultDownloadDirectory();
  }

  bool get _canPickDirectory => supportsCustomDownloadDirectory;

  bool get _hasCustomDirectory =>
      _canPickDirectory && downloadDirectory.isNotEmpty;

  String get _effectiveDownloadDirectory =>
      _hasCustomDirectory ? downloadDirectory : defaultDownloadDirectory;

  Future<void> _loadDefaultDownloadDirectory() async {
    final directory = await getDefaultDownloadDirectory();
    if (!mounted) return;
    setState(() {
      defaultDownloadDirectory = directory;
    });
  }

  /// 申请写入自定义下载目录所需的存储权限。
  /// Android 11+（SDK>=30）需"所有文件访问"(MANAGE_EXTERNAL_STORAGE)，会跳转系统设置页；
  /// Android 10- 申请运行时读写外部存储权限。
  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
        return status.isGranted;
      } else {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        return status.isGranted;
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _selectDownloadDirectory() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_canPickDirectory) {
      KazumiDialog.showToast(message: l10n.setAPlatformNoDir);
      return;
    }
    if (isSelectingDirectory) return;

    setState(() => isSelectingDirectory = true);
    try {
      String? selectedPath;

      if (Platform.isAndroid) {
        // Android: 直接用 SAF 目录选择器选「文件夹」（「使用此文件夹」授权）
        selectedPath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: l10n.setAPickDir,
        );
      } else {
        // 桌面平台: 直接选择目录
        final effectiveDirectory = _effectiveDownloadDirectory;
        final initialDirectory = effectiveDirectory.isNotEmpty &&
                await Directory(effectiveDirectory).exists()
            ? effectiveDirectory
            : null;
        selectedPath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: l10n.setAPickDir,
          initialDirectory: initialDirectory,
        );
      }

      if (selectedPath == null || selectedPath.isEmpty) return;

      if (Platform.isAndroid && !await _requestStoragePermission()) {
        KazumiDialog.showToast(message: l10n.setADirWriteFail(msg: '需要存储权限才能写入该目录，请在系统设置中授权后重试'));
        return;
      }

      await ensureDirectoryWritable(selectedPath);
      if (!Platform.isAndroid) {
        // 桌面平台需要持久访问权限
        if (!await SecureBookmarkService.persist(selectedPath)) {
          KazumiDialog.showToast(message: l10n.setAPersistPermFail);
          return;
        }
      }
      await GStorage.putSetting(
        SettingsKeys.downloadDirectory,
        selectedPath,
      );
      if (mounted) {
        setState(() => downloadDirectory = selectedPath!);
      }
      KazumiDialog.showToast(message: l10n.setADirUpdated);
    } on FileSystemException catch (e) {
      KazumiDialog.showToast(message: l10n.setADirWriteFail(msg: e.message));
    } catch (e) {
      KazumiDialog.showToast(message: l10n.setAPickDirFail(err: e.toString()));
    } finally {
      if (mounted) {
        setState(() => isSelectingDirectory = false);
      }
    }
  }

  Future<void> _resetDownloadDirectory() async {
    await SecureBookmarkService.clear();
    await GStorage.putSetting(SettingsKeys.downloadDirectory, '');
    if (mounted) {
      setState(() => downloadDirectory = '');
    }
    KazumiDialog.showToast(message: AppLocalizations.of(context)!.setADirResetDone);
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SysAppBar(title: Text(l10n.downloadSettings)),
      body: SettingsList(
        maxWidth: 1000,
        sections: [
          SettingsSection(
            title: Text(l10n.setAConcurrency, style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile(
                title: Text(l10n.setAParallelEpisodes, style: TextStyle(fontFamily: fontFamily)),
                description: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.setAParallelEpisodesValue(count: parallelEpisodes),
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                    Slider(
                      value: parallelEpisodes.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '$parallelEpisodes',
                      onChanged: (value) {
                        setState(() => parallelEpisodes = value.toInt());
                        GStorage.putSetting(
                          SettingsKeys.downloadParallelEpisodes,
                          parallelEpisodes,
                        );
                      },
                    ),
                  ],
                ),
              ),
              SettingsTile(
                title: Text(l10n.setAParallelSegments, style: TextStyle(fontFamily: fontFamily)),
                description: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.setAParallelSegmentsValue(count: parallelSegments),
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                    Slider(
                      value: parallelSegments.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '$parallelSegments',
                      onChanged: (value) {
                        setState(() => parallelSegments = value.toInt());
                        GStorage.putSetting(
                          SettingsKeys.downloadParallelSegments,
                          parallelSegments,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.setACacheSettings, style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile(
                title: Text(l10n.setADownloadDir, style: TextStyle(fontFamily: fontFamily)),
                description: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _effectiveDownloadDirectory.isEmpty
                          ? l10n.setAReadingDefaultDir
                          : _effectiveDownloadDirectory,
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hasCustomDirectory
                          ? l10n.setACustomDirHint
                          : l10n.setADefaultDirHint,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontFamily: fontFamily,
                      ),
                    ),
                  ],
                ),
                trailing: isSelectingDirectory
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _hasCustomDirectory
                        ? IconButton(
                            tooltip: l10n.setARestoreDefault,
                            icon: const Icon(Icons.restore_rounded),
                            onPressed: _resetDownloadDirectory,
                          )
                        : null,
                onPressed: (_) => _selectDownloadDirectory(),
              ),
              SettingsTile.switchTile(
                onToggle: (value) {
                  setState(() => downloadDanmaku = value ?? !downloadDanmaku);
                  GStorage.putSetting(
                      SettingsKeys.downloadDanmaku, downloadDanmaku);
                },
                title: Text(l10n.setACacheDanmaku, style: TextStyle(fontFamily: fontFamily)),
                description: Text(
                  l10n.setACacheDanmakuDesc,
                  style: TextStyle(fontFamily: fontFamily),
                ),
                initialValue: downloadDanmaku,
              ),
              SettingsTile.switchTile(
                onToggle: (value) {
                  setState(() => downloadNotify = value ?? !downloadNotify);
                  GStorage.putSetting(
                      SettingsKeys.downloadCompleteNotify, downloadNotify);
                },
                title: Text(l10n.setADownloadDoneNotify,
                    style: TextStyle(fontFamily: fontFamily)),
                description: Text(
                  l10n.setADownloadDoneNotifyDesc,
                  style: TextStyle(fontFamily: fontFamily),
                ),
                initialValue: downloadNotify,
              ),
              SettingsTile.switchTile(
                onToggle: (value) {
                  setState(() => downloadWifiOnly = value ?? !downloadWifiOnly);
                  GStorage.putSetting(
                      SettingsKeys.downloadWifiOnly, downloadWifiOnly);
                },
                title: Text('仅 WiFi 下载',
                    style: TextStyle(fontFamily: fontFamily)),
                description: Text(
                  '开启后仅在 WiFi/有线网络下开始下载，移动数据下先排队',
                  style: TextStyle(fontFamily: fontFamily),
                ),
                initialValue: downloadWifiOnly,
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.setANotes, style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile(
                title: Text(l10n.setAAboutConcurrency, style: TextStyle(fontFamily: fontFamily)),
                description: Text(
                  l10n.setAConcurrencyHelp,
                  style: TextStyle(fontFamily: fontFamily),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

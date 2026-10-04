import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/sync_priority.dart';
import 'package:kazumi/services/sync/bangumi_sync_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class BangumiEditorPage extends StatefulWidget {
  const BangumiEditorPage({super.key});

  @override
  State<BangumiEditorPage> createState() => _BangumiEditorPageState();
}

class _BangumiEditorPageState extends State<BangumiEditorPage> {
  final TextEditingController bangumiTokenController = TextEditingController();
  bool passwordVisible = false;
  bool isVerifying = false;
  late bool bangumiImmediateSyncToastEnable;
  late int syncPriority;
  bool syncCollectiblesing = false;
  final MenuController syncPriorityMenuController = MenuController();

  @override
  void initState() {
    super.initState();
    bangumiTokenController.text =
        GStorage.getSetting(SettingsKeys.bangumiAccessToken);
    bangumiImmediateSyncToastEnable =
        GStorage.getSetting(SettingsKeys.bangumiImmediateSyncToastEnable);
    syncPriority = GStorage.getSetting(SettingsKeys.bangumiSyncPriority);
  }

  @override
  void dispose() {
    bangumiTokenController.dispose();
    super.dispose();
  }

  Future<void> updateSyncPriority(int value) async {
    await GStorage.putSetting(SettingsKeys.bangumiSyncPriority, value);
    if (!mounted) return;
    setState(() {
      syncPriority = value;
    });
  }

  Future<void> syncWithProgress() async {
    final l10n = AppLocalizations.of(context)!;
    final syncEnable = GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    if (!syncEnable) {
      KazumiDialog.showToast(message: l10n.setCEnableBangumiSyncFirst);
      return;
    }

    final progressDialogKey = GlobalKey<_BangumiSyncProgressDialogState>();

    try {
      setState(() {
        syncCollectiblesing = true;
      });

      KazumiDialog.show(
        clickMaskDismiss: false,
        builder: (context) =>
            _BangumiSyncProgressDialog(key: progressDialogKey),
      );

      final bangumi = BangumiSyncService();
      await bangumi.ping();
      await bangumi.syncCollectibles(
        onProgress: (message, current, total) {
          progressDialogKey.currentState?.update(
            total > 0 ? '$message ($current/$total)' : message,
            total > 0 ? (current / total).clamp(0.0, 1.0).toDouble() : null,
          );
        },
      );
    } catch (e) {
      KazumiDialog.showToast(message: l10n.setCBangumiSyncFailed(error: e.toString()));
    } finally {
      if (KazumiDialog.observer.hasKazumiDialog) {
        KazumiDialog.dismiss();
      }
      if (mounted) {
        setState(() {
          syncCollectiblesing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !syncCollectiblesing,
      child: Scaffold(
        appBar: SysAppBar(title: Text(l10n.setCBangumiConfig)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: SizedBox(
              width: (MediaQuery.of(context).size.width > 1000) ? 1000 : null,
              child: Column(
                children: [
                  TextField(
                    controller: bangumiTokenController,
                    obscureText: !passwordVisible,
                    decoration: InputDecoration(
                      labelText: 'Bangumi Access Token',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            passwordVisible = !passwordVisible;
                          });
                        },
                        icon: Icon(passwordVisible
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SettingsSection(
                    margin: EdgeInsetsDirectional.zero,
                    tiles: [
                      SettingsTile.switchTile(
                        onToggle: (value) async {
                          bangumiImmediateSyncToastEnable =
                              value ?? !bangumiImmediateSyncToastEnable;
                          await GStorage.putSetting(
                            SettingsKeys.bangumiImmediateSyncToastEnable,
                            bangumiImmediateSyncToastEnable,
                          );
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        title: Text(l10n.setCImmediateSyncToast,
                            style: TextStyle(fontFamily: fontFamily)),
                        description: Text(l10n.setCImmediateSyncToastDesc,
                            style: TextStyle(fontFamily: fontFamily)),
                        initialValue: bangumiImmediateSyncToastEnable,
                      ),
                      SettingsTile.navigation(
                        onPressed: (_) async {
                          if (syncPriorityMenuController.isOpen) {
                            syncPriorityMenuController.close();
                          } else {
                            syncPriorityMenuController.open();
                          }
                        },
                        title: Text(l10n.setCSyncPriority,
                            style: TextStyle(fontFamily: fontFamily)),
                        description: Text(l10n.setCSyncPriorityDesc,
                            style: TextStyle(fontFamily: fontFamily)),
                        value: MenuAnchor(
                            consumeOutsideTap: true,
                            controller: syncPriorityMenuController,
                            builder: (context, controller, child) => Text(
                                BangumiSyncPriority.fromValue(syncPriority)
                                    .label,
                                style: TextStyle(fontFamily: fontFamily)),
                            menuChildren: [
                              for (final entry in BangumiSyncPriority.values)
                                MenuItemButton(
                                    requestFocusOnHover: false,
                                    onPressed: () =>
                                        updateSyncPriority(entry.value),
                                    child: Container(
                                        height: 48,
                                        constraints:
                                            BoxConstraints(minWidth: 112),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            entry.label,
                                            style: TextStyle(
                                              color: entry.value == syncPriority
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                  : null,
                                              fontFamily: fontFamily,
                                            ),
                                          ),
                                        )))
                            ]),
                      ),
                      SettingsTile(
                        trailing: syncCollectiblesing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync_rounded),
                        onPressed: (_) async {
                          await syncWithProgress();
                        },
                        title: Text(l10n.setCSyncNow,
                            style: TextStyle(fontFamily: fontFamily)),
                        description: Text(l10n.setCSyncNowDesc,
                            style: TextStyle(fontFamily: fontFamily)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () async {
                      final url =
                          Uri.parse('https://next.bgm.tv/demo/access-token');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                      } else {
                        KazumiDialog.showToast(message: l10n.setCCannotOpenLink);
                      }
                    },
                    child: Text(
                      l10n.setCGetTokenHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontFamily: fontFamily,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: isVerifying
              ? null
              : () async {
                  final token = bangumiTokenController.text.trim();
                  final bool bangumiSyncEnable =
                      GStorage.getSetting(SettingsKeys.bangumiSyncEnable);

                  if (token.isEmpty && bangumiSyncEnable) {
                    KazumiDialog.showToast(message: l10n.setCTokenEmpty);
                    return;
                  }
                  setState(() {
                    isVerifying = true;
                  });
                  await GStorage.putSetting(
                      SettingsKeys.bangumiAccessToken, token);
                  final bangumi = BangumiSyncService();

                  if (token.isEmpty) {
                    bangumi.reset();
                    KazumiDialog.showToast(message: l10n.setCBangumiTokenEmpty);
                    if (!mounted) return;
                    setState(() {
                      isVerifying = false;
                    });
                    return;
                  }

                  KazumiDialog.showToast(message: l10n.setCTestingBangumiToken);
                  try {
                    await bangumi.init();
                  } catch (e) {
                    KazumiDialog.showToast(message: l10n.setCVerifyFailed(error: e.toString()));
                    await GStorage.putSetting(
                        SettingsKeys.bangumiSyncEnable, false);
                    if (!mounted) return;
                    setState(() {
                      isVerifying = false;
                    });
                    return;
                  }

                  KazumiDialog.showToast(
                      message: l10n.setCTestSuccessUser(user: bangumi.username));
                  if (!mounted) return;
                  setState(() {
                    isVerifying = false;
                  });
                },
          child: const Icon(Icons.save),
        ),
      ),
    );
  }
}

class _BangumiSyncProgressDialog extends StatefulWidget {
  const _BangumiSyncProgressDialog({super.key});

  @override
  State<_BangumiSyncProgressDialog> createState() =>
      _BangumiSyncProgressDialogState();
}

class _BangumiSyncProgressDialogState
    extends State<_BangumiSyncProgressDialog> {
  late String _progressText;
  double? _progressValue;

  @override
  void initState() {
    super.initState();
    _progressText = AppLocalizations.of(context)!.setCPreparingSync;
  }

  void update(String text, double? value) {
    if (!mounted) return;
    setState(() {
      _progressText = text;
      _progressValue = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.setCBangumiSyncing,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(_progressText),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progressValue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

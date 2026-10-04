import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

/// 解析本地化实例：优先使用调用方传入的 context，否则回退到全局 navigator context。
/// （经验判断：本函数被范围外页面以无 context 形式调用，回退保证其在运行期仍可本地化。）
AppLocalizations _l10nOf(BuildContext? context) {
  final ctx = context ?? rootNavigatorKey.currentContext;
  return AppLocalizations.of(ctx!)!;
}

Future<void> updateAllPluginsWithFeedback(
  PluginsController controller, {
  required bool ensureCatalog,
  BuildContext? context,
}) async {
  final l10n = _l10nOf(context);
  KazumiDialog.showLoading(msg: l10n.setFUpdating);
  try {
    final result = await controller.tryUpdateAllPlugin(
      ensureCatalog: ensureCatalog,
    );
    KazumiDialog.dismiss();
    KazumiDialog.showToast(message: _batchUpdateMessage(result, l10n));
  } catch (_) {
    KazumiDialog.dismiss();
    KazumiDialog.showToast(message: l10n.setFUpdateRuleFailed);
  }
}

Future<PluginUpdateResult> updatePluginWithFeedback(
  PluginsController controller,
  String name, {
  required bool installing,
  BuildContext? context,
}) async {
  final l10n = _l10nOf(context);
  KazumiDialog.showToast(message: installing ? l10n.setFImporting : l10n.setFUpdating);
  late final PluginUpdateResult result;
  try {
    result = await controller.tryUpdatePluginByName(name);
  } catch (_) {
    KazumiDialog.showToast(message: l10n.setFSaveRuleFailed);
    return PluginUpdateResult.failed;
  }
  final message = switch (result) {
    PluginUpdateResult.updated => installing ? l10n.setFImportSuccess : l10n.setFUpdateSuccess,
    PluginUpdateResult.requiresNewerClient => l10n.setFRequiresNewerClient,
    PluginUpdateResult.failed => installing ? l10n.setFImportRuleFailed : l10n.setFUpdateRuleFailed,
    PluginUpdateResult.notNewer => l10n.setFNotNewer,
  };
  KazumiDialog.showToast(message: message);
  return result;
}

String _batchUpdateMessage(PluginBatchUpdateResult result, AppLocalizations l10n) {
  if (result.hasNoCandidates) {
    return l10n.setFNoUpdateCandidates;
  }
  if (result.failed == 0 &&
      result.requiresNewerClient == 0 &&
      result.notNewer == 0) {
    return l10n.setFBatchUpdated(count: result.updated);
  }

  final parts = <String>[l10n.setFBatchSucceeded(count: result.updated)];
  if (result.requiresNewerClient > 0) {
    parts.add(l10n.setFBatchIncompatible(count: result.requiresNewerClient));
  }
  if (result.notNewer > 0) {
    parts.add(l10n.setFBatchSkipped(count: result.notNewer));
  }
  if (result.failed > 0) {
    parts.add(l10n.setFBatchFailed(count: result.failed));
  }
  return l10n.setFBatchUpdateDone(parts: parts.join(', '));
}

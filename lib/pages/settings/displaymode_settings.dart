import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:kazumi/l10n/app_localizations.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:card_settings_ui/card_settings_ui.dart';

class SetDisplayMode extends StatefulWidget {
  const SetDisplayMode({super.key});

  @override
  State<SetDisplayMode> createState() => _SetDisplayModeState();
}

class _SetDisplayModeState extends State<SetDisplayMode> {
  List<DisplayMode> modes = <DisplayMode>[];
  DisplayMode? active;
  DisplayMode? preferred;

  final ValueNotifier<int> page = ValueNotifier<int>(0);
  late final PageController controller = PageController()
    ..addListener(() {
      page.value = controller.page!.round();
    });

  @override
  void initState() {
    super.initState();
    init();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      fetchAll();
    });
  }

  Future<void> fetchAll() async {
    preferred = await FlutterDisplayMode.preferred;
    active = await FlutterDisplayMode.active;
    await GStorage.putSetting(SettingsKeys.displayMode, preferred.toString());
    setState(() {});
  }

  Future<void> init() async {
    try {
      modes = await FlutterDisplayMode.supported;
    } on PlatformException catch (_) {}
    var res = await getDisplayModeType(modes);

    preferred = modes.toList().firstWhere((el) => el == res);
    FlutterDisplayMode.setPreferredMode(preferred!);
  }

  Future<DisplayMode> getDisplayModeType(modes) async {
    var value = GStorage.getSetting(SettingsKeys.displayMode);
    DisplayMode f = DisplayMode.auto;
    if (value != null) {
      f = modes.firstWhere((e) => e.toString() == value);
    }
    return f;
  }

  @override
  void dispose() {
    controller.dispose();
    page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setARefreshRate)),
      body: (modes.isEmpty)
          ? const LoadingIndicator()
          : SettingsList(
              maxWidth: 1000,
              sections: [
                SettingsSection(
                  title: Text(l10n.setARefreshRateHint,
                      style: TextStyle(fontFamily: fontFamily)),
                  tiles: modes
                      .map((e) => SettingsTile<DisplayMode>.radioTile(
                            radioValue: e,
                            groupValue: preferred,
                            onChanged: (DisplayMode? newMode) async {
                              await FlutterDisplayMode.setPreferredMode(
                                  newMode!);
                              await Future<dynamic>.delayed(
                                const Duration(milliseconds: 100),
                              );
                              await fetchAll();
                            },
                            title: e == DisplayMode.auto
                                ? Text(l10n.setAAutoMode,
                                    style: TextStyle(fontFamily: fontFamily))
                                : Text('$e${e == active ? l10n.setASystemSuffix : ""}',
                                    style: TextStyle(fontFamily: fontFamily)),
                          ))
                      .toList(),
                ),
              ],
            ),
    );
  }
}

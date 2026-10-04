import 'package:flutter/material.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/l10n/app_localizations.dart';

class DanmakuShieldSettings extends StatefulWidget {
  const DanmakuShieldSettings({super.key});

  @override
  State<DanmakuShieldSettings> createState() => _DanmakuShieldSettingsState();
}

class _DanmakuShieldSettingsState extends State<DanmakuShieldSettings> {
  final MyController myController = inject<MyController>();
  final TextEditingController textEditingController = TextEditingController();

  @override
  void dispose() {
    textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SysAppBar(
        title: Text(l10n.setBDanmakuFilter),
      ),
      body: ListView(
        padding: EdgeInsets.all(12),
        children: [
          TextField(
            controller: textEditingController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: l10n.setBKeywordOrRegexHint,
              suffixIcon: TextButton.icon(
                onPressed: () {
                  myController.addShieldList(
                    textEditingController.text.trim(),
                  );
                },
                icon: const Icon(Icons.add),
                label: Text(l10n.setBAdd),
              ),
            ),
            onSubmitted: (_) {
              myController.addShieldList(
                textEditingController.text.trim(),
              );
            },
          ),
          SizedBox(height: 12),
          Text(
            l10n.setBShieldRegexHint,
          ),
          Observer(builder: (context) {
            return Text(
              l10n.setBKeywordCount(count: myController.shieldList.length),
            );
          }),
          SizedBox(height: 12),
          Observer(builder: (context) {
            return Wrap(
              runSpacing: 12,
              spacing: 12,
              children: myController.shieldList
                  .map(
                    (item) => Chip(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32)),
                      backgroundColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide.none,
                      label: Text(
                        item,
                        style: TextStyle(
                          fontSize: 14,
                        ),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      deleteIcon: Icon(Icons.close, size: 18),
                      deleteButtonTooltipMessage: '',
                      onDeleted: () {
                        myController.removeShieldList(item);
                      },
                    ),
                  )
                  .toList(),
            );
          })
        ],
      ),
    );
  }
}

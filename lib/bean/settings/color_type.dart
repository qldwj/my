import 'package:flutter/material.dart';

/// Each entry's [labelKey] is an arb key name resolved against AppLocalizations
/// at render time in theme_settings_page.dart.
final List<Map<String, dynamic>> colorThemeTypes = [
  {'color': const Color(0xFFFF6FA5), 'labelKey': 'setDColorDefault'},
  {'color': Colors.teal, 'labelKey': 'setDColorTeal'},
  {'color': Colors.blue, 'labelKey': 'setDColorBlue'},
  {'color': Colors.indigo, 'labelKey': 'setDColorIndigo'},
  {'color': const Color(0xff6750a4), 'labelKey': 'setDColorViolet'},
  {'color': Colors.yellow, 'labelKey': 'setDColorYellow'},
  {'color': Colors.orange, 'labelKey': 'setDColorOrange'},
  {'color': Colors.deepOrange, 'labelKey': 'setDColorDeepOrange'},
  {'color': Colors.white, 'labelKey': 'setDColorWhite'},
];

import 'dart:convert';
import 'dart:io';

import 'package:kazumi/plugins/animeko_rule_config.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';

/// Converts Animeko web-selector and rss rules to Kazumi Plugin objects.
///
/// Each Animeko rule becomes a Plugin with [RuleMode.css] or [RuleMode.rss],
/// and the full Animeko config stored in [Plugin.animekoConfig] (for web-selector).
class AnimekoRuleConverter {
  /// Converts an Animeko exported media source list JSON string into a list
  /// of Kazumi Plugin objects.
  ///
  /// Expected JSON structure:
  /// ```json
  /// {
  ///   "exportedMediaSourceDataList": {
  ///     "mediaSources": [
  ///       {
  ///         "factoryId": "web-selector",
  ///         "version": 2,
  ///         "arguments": { ... }
  ///       },
  ///       ...
  ///     ]
  ///   }
  /// }
  /// ```
  static List<Plugin> convertFromJson(String jsonString) {
    final List<Plugin> plugins = [];

    try {
      final dynamic decoded = jsonDecode(jsonString);

      // Support both the wrapped format and a direct array
      List<dynamic> sources;
      if (decoded is Map) {
        final mediaSourceData = decoded['exportedMediaSourceDataList'];
        if (mediaSourceData is Map) {
          sources = (mediaSourceData['mediaSources'] as List<dynamic>?) ?? [];
        } else {
          sources = decoded['mediaSources'] as List<dynamic>? ?? [];
        }
      } else if (decoded is List) {
        sources = decoded;
      } else {
        return plugins;
      }

      for (final sourceJson in sources) {
        if (sourceJson is! Map) continue;

        final factoryId = sourceJson['factoryId'] as String? ?? '';

        final argsRaw = sourceJson['arguments'];
        if (argsRaw is! Map) continue;
        final args = Map<String, dynamic>.from(argsRaw as Map);

        try {
          final plugin = convertSingleRule(args, factoryId: factoryId);
          if (plugin != null) {
            plugins.add(plugin);
          }
        } catch (e) {
          // Skip rules that fail to convert
          continue;
        }
      }
    } catch (e) {
      // Return whatever we have
    }

    return plugins;
  }

  /// Converts a single Animeko rule arguments map to a Plugin.
  ///
  /// [factoryId] determines the conversion strategy:
  /// - `web-selector` → CSS mode with full animekoConfig
  /// - `rss` → RSS mode with searchURL pointing to the feed
  static Plugin? convertSingleRule(
    Map<String, dynamic> args, {
    String factoryId = 'web-selector',
  }) {
    final name = args['name'] as String? ?? '';
    if (name.isEmpty) return null;

    final description = args['description'] as String? ?? '';

    if (factoryId == 'rss') {
      return _convertRssRule(name, description, args);
    }

    // Default: web-selector
    return _convertWebSelectorRule(name, description, args);
  }

  static Plugin? _convertWebSelectorRule(
    String name,
    String description,
    Map<String, dynamic> args,
  ) {
    final searchConfigRaw = args['searchConfig'];
    if (searchConfigRaw is! Map) return null;
    final searchConfigJson = Map<String, dynamic>.from(searchConfigRaw as Map);

    final searchConfig = AnimekoSearchConfig.fromJson(searchConfigJson);
    final searchUrl = searchConfig.searchUrl;
    final baseUrl = _extractBaseUrl(searchUrl);

    return Plugin(
      api: '5',
      type: 'anime',
      name: name,
      version: '1.0',
      muliSources: true,
      useWebview: true,
      useNativePlayer: true,
      usePost: false,
      useLegacyParser: false,
      adBlocker: description.contains('NSFW') ? false : true,
      userAgent: '',
      baseUrl: baseUrl,
      searchURL: searchUrl,
      searchList: '',
      searchName: '',
      searchResult: '',
      chapterRoads: '',
      chapterResult: '',
      referer: baseUrl,
      searchMode: RuleMode.css,
      chapterMode: RuleMode.css,
      enabled: true,
      animekoConfig: AnimekoWebSelectorRule(
        name: name,
        description: description,
        iconUrl: args['iconUrl'] as String? ?? '',
        searchConfig: searchConfig,
        tier: args['tier'] as int? ?? 3,
      ),
    );
  }

  static Plugin? _convertRssRule(
    String name,
    String description,
    Map<String, dynamic> args,
  ) {
    final searchConfigRaw = args['searchConfig'];
    String searchUrl;

    if (searchConfigRaw is Map) {
      final searchConfigJson = Map<String, dynamic>.from(searchConfigRaw as Map);
      searchUrl = searchConfigJson['searchUrl'] as String? ?? '';
    } else {
      // Some RSS rules have searchUrl directly in args
      searchUrl = args['searchUrl'] as String? ?? '';
    }

    if (searchUrl.isEmpty) return null;

    final baseUrl = _extractBaseUrl(searchUrl);

    return Plugin(
      api: '5',
      type: 'anime',
      name: name,
      version: '1.0',
      muliSources: false,
      useWebview: false,
      useNativePlayer: true,
      usePost: false,
      useLegacyParser: false,
      adBlocker: false,
      userAgent: '',
      baseUrl: baseUrl,
      searchURL: searchUrl,
      searchList: '',
      searchName: '',
      searchResult: '',
      chapterRoads: '',
      chapterResult: '',
      referer: baseUrl,
      searchMode: RuleMode.rss,
      chapterMode: RuleMode.rss,
      enabled: true,
    );
  }

  /// Converts and saves Animeko rules to the Kazumi plugins JSON file.
  ///
  /// [inputJson] is the Animeko JSON string.
  /// [outputPath] is the path where Kazumi's plugins.json should be written.
  /// If [append] is true, existing plugins are preserved and new ones added.
  static Future<int> convertAndSave(
    String inputJson,
    String outputPath, {
    bool append = false,
  }) async {
    final newPlugins = convertFromJson(inputJson);
    if (newPlugins.isEmpty) return 0;

    List<Plugin> existing = [];
    if (append) {
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        try {
          final existingJson = await outputFile.readAsString();
          final existingList = jsonDecode(existingJson) as List<dynamic>;
          existing = existingList
              .map((e) => Plugin.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }
    }

    // Merge: add only plugins that don't already exist (by name)
    final existingNames = existing.map((p) => p.name).toSet();
    for (final plugin in newPlugins) {
      if (!existingNames.contains(plugin.name)) {
        existing.add(plugin);
        existingNames.add(plugin.name);
      }
    }

    final outputFile = File(outputPath);
    await outputFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        existing.map((p) => p.toJson()).toList(),
      ),
    );

    return newPlugins.length;
  }

  static String _extractBaseUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return url;
    }
  }
}

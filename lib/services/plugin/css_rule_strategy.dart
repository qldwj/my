import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/animeko_rule_config.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/utils/episode_url.dart';

/// Exception thrown when a CSS rule format is invalid.
class CssRuleFormatException implements Exception {
  const CssRuleFormatException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'CssRuleFormatException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Strategy for executing Animeko web-selector rules using CSS selectors.
///
/// This strategy uses the `html` Dart package's built-in `querySelector` /
/// `querySelectorAll` methods, which support standard CSS selectors, to
/// navigate HTML pages and extract data according to Animeko's rule format.
class CssRuleStrategy {
  const CssRuleStrategy();

  // ------------------------------------------------------------------
  // Search
  // ------------------------------------------------------------------

  /// Prepares a search request from an Animeko rule.
  PreparedRuleRequest prepareSearchRequest(
    AnimekoWebSelectorRule rule,
    String keyword,
  ) {
    final url = rule.searchConfig.searchUrl.replaceAll(
      '{keyword}',
      Uri.encodeQueryComponent(keyword),
    );
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw CssRuleFormatException('搜索 URL 无效: $url');
    }
    return PreparedRuleRequest(
      method: 'GET',
      url: url,
      includeCookies: true,
    );
  }

  /// Parses search results from raw HTML using Animeko's subject format.
  RuleSearchParseResult parseSearch(
    String raw,
    AnimekoWebSelectorRule rule,
  ) {
    final root = _parseHtml(raw);
    final config = rule.searchConfig;
    final diagnostics = <String>[];
    final matches = <String>[];

    final items = <SearchItem>[];

    if (config.subjectFormatId == 'indexed' &&
        config.selectorSubjectFormatIndexed != null) {
      // Indexed format: separate selectors for names and links
      items.addAll(_parseSearchIndexed(
        root,
        config.selectorSubjectFormatIndexed!,
        config.searchUrl,
        diagnostics,
      ));
    } else if (config.selectorSubjectFormatA != null) {
      // Simple <a> format
      items.addAll(_parseSearchAFormat(
        root,
        config.selectorSubjectFormatA!,
        config.searchUrl,
        diagnostics,
      ));
    }

    for (final item in items) {
      matches.add(item.name);
    }

    return RuleSearchParseResult(
      items: items,
      matchedFragments: matches,
      diagnostics: diagnostics,
    );
  }

  List<SearchItem> _parseSearchAFormat(
    Element root,
    AnimekoSelectorSubjectFormatA format,
    String searchUrl,
    List<String> diagnostics,
  ) {
    final results = <SearchItem>[];
    try {
      final listSelector = format.selectLists;
      if (listSelector.isEmpty) return results;

      final links = root.querySelectorAll(listSelector);
      for (var index = 0; index < links.length; index++) {
        try {
          final anchor = links[index];
          final name = anchor.text.trim();
          final href = anchor.attributes['href']?.trim() ?? '';
          if (name.isEmpty || href.isEmpty) {
            diagnostics.add('搜索结果节点 $index 缺少名称或链接，已跳过');
            continue;
          }
          results.add(SearchItem(name: name, src: href));
        } catch (e) {
          diagnostics.add('搜索结果节点 $index 解析失败: $e');
        }
      }
    } catch (e) {
      diagnostics.add('搜索列表选择器执行失败: $e');
    }
    return results;
  }

  List<SearchItem> _parseSearchIndexed(
    Element root,
    AnimekoSelectorSubjectFormatIndexed format,
    String searchUrl,
    List<String> diagnostics,
  ) {
    final results = <SearchItem>[];
    try {
      final nameSelector = format.selectNames;
      final linkSelector = format.selectLinks;
      if (nameSelector.isEmpty || linkSelector.isEmpty) return results;

      final nameNodes = root.querySelectorAll(nameSelector);
      final linkNodes = root.querySelectorAll(linkSelector);

      final count =
          nameNodes.length < linkNodes.length
              ? nameNodes.length
              : linkNodes.length;
      for (var index = 0; index < count; index++) {
        try {
          final name = nameNodes[index].text.trim();
          final href = linkNodes[index].attributes['href']?.trim() ?? '';
          if (name.isEmpty || href.isEmpty) {
            diagnostics.add('搜索结果节点 $index 缺少名称或链接，已跳过');
            continue;
          }
          results.add(SearchItem(name: name, src: href));
        } catch (e) {
          diagnostics.add('搜索结果节点 $index 解析失败: $e');
        }
      }
    } catch (e) {
      diagnostics.add('搜索列表选择器执行失败: $e');
    }
    return results;
  }

  // ------------------------------------------------------------------
  // Chapters (播放线路 + 剧集列表)
  // ------------------------------------------------------------------

  /// Prepares a chapter/playback page request.
  PreparedRuleRequest prepareChapterRequest(
    AnimekoWebSelectorRule rule,
    String source,
  ) {
    // source is typically a relative path from search result
    final baseUrl = _extractBaseUrl(rule.searchConfig.searchUrl);
    final url = normalizeEpisodeUrl(baseUrl, source);
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw CssRuleFormatException('章节 URL 无效: $url');
    }
    return PreparedRuleRequest(method: 'GET', url: url);
  }

  /// Parses chapter/road/episode data from the detail page HTML.
  RuleChapterParseResult parseChapters(
    String raw,
    AnimekoWebSelectorRule rule,
  ) {
    final root = _parseHtml(raw);
    final config = rule.searchConfig;
    final diagnostics = <String>[];
    final roads = <Road>[];

    try {
      if (config.channelFormatId == 'index-grouped' &&
          config.selectorChannelFormatFlattened != null) {
        roads.addAll(_parseFlattenedChannels(
          root,
          config.selectorChannelFormatFlattened!,
          config.searchUrl,
          diagnostics,
        ));
      } else if (config.selectorChannelFormatNoChannel != null) {
        roads.addAll(_parseNoChannelEpisodes(
          root,
          config.selectorChannelFormatNoChannel!,
          config.searchUrl,
          diagnostics,
        ));
      }
    } catch (e) {
      diagnostics.add('章节解析失败: $e');
    }

    if (roads.isEmpty) {
      // Fallback: try to find any links on the page as episodes
      roads.addAll(_fallbackEpisodeParse(root, config.searchUrl, diagnostics));
    }

    return RuleChapterParseResult(roads: roads, diagnostics: diagnostics);
  }

  List<Road> _parseFlattenedChannels(
    Element root,
    AnimekoSelectorChannelFormatFlattened format,
    String searchUrl,
    List<String> diagnostics,
  ) {
    final baseUrl = _extractBaseUrl(searchUrl);
    final roads = <Road>[];

    // 1. Find channel tab names
    final channelNameSelector = format.selectChannelNames;
    List<Element> channelNameNodes;
    try {
      channelNameNodes =
          channelNameSelector.isNotEmpty
              ? root.querySelectorAll(channelNameSelector)
              : [];
    } catch (e) {
      diagnostics.add('频道名称选择器失败: $e');
      channelNameNodes = [];
    }

    // 2. Find episode list containers
    final episodeListSelector = format.selectEpisodeLists;
    List<Element> episodeListNodes;
    try {
      episodeListNodes =
          episodeListSelector.isNotEmpty
              ? root.querySelectorAll(episodeListSelector)
              : [];
    } catch (e) {
      diagnostics.add('剧集列表选择器失败: $e');
      episodeListNodes = [];
    }

    // 3. Match channels to episode lists by index
    final channelCount = episodeListNodes.length;
    for (var channelIndex = 0;
        channelIndex < channelCount;
        channelIndex++) {
      try {
        String channelName =
            channelIndex < channelNameNodes.length
                ? channelNameNodes[channelIndex].text.trim()
                : '';

        // Apply matchChannelName regex if configured
        if (channelName.isNotEmpty &&
            format.matchChannelName.isNotEmpty) {
          try {
            final regex = RegExp(format.matchChannelName);
            final match = regex.firstMatch(channelName);
            if (match != null && match.namedGroup('ch') != null) {
              channelName = match.namedGroup('ch')!;
            }
          } catch (_) {}
        }

        if (channelName.isEmpty) {
          channelName = '播放线路${roads.length + 1}';
        }

        // 4. Extract episodes from this list
        final listContainer = episodeListNodes[channelIndex];
        final episodeSelector = format.selectEpisodesFromList;
        final episodeLinkSelector = format.selectEpisodeLinksFromList;

        List<Element> episodeAnchors;
        try {
          episodeAnchors = listContainer.querySelectorAll(episodeSelector);
        } catch (e) {
          diagnostics.add('线路 $channelIndex 剧集选择器失败: $e');
          episodeAnchors = [];
        }

        final urls = <String>[];
        final names = <String>[];
        for (var epIndex = 0;
            epIndex < episodeAnchors.length;
            epIndex++) {
          try {
            final anchor = episodeAnchors[epIndex];
            String href;

            // If episodeLinkSelector is specified, find the actual <a>
            if (episodeLinkSelector.isNotEmpty) {
              final linkEl = anchor.querySelector(episodeLinkSelector);
              href = linkEl?.attributes['href']?.trim() ?? '';
            } else {
              href = anchor.attributes['href']?.trim() ?? '';
            }

            if (href.isEmpty) continue;

            String epName = _cleanEpisodeName(anchor.text, format.matchEpisodeSortFromName, epIndex);

            urls.add(normalizeEpisodeUrl(baseUrl, href));
            names.add(epName);
          } catch (e) {
            diagnostics.add('线路 $channelIndex 剧集 $epIndex 解析失败: $e');
          }
        }

        if (urls.isNotEmpty) {
          roads.add(Road(name: channelName, data: urls, identifier: names));
        }
      } catch (e) {
        diagnostics.add('线路 $channelIndex 解析失败: $e');
      }
    }

    return roads;
  }

  List<Road> _parseNoChannelEpisodes(
    Element root,
    AnimekoSelectorChannelFormatNoChannel format,
    String searchUrl,
    List<String> diagnostics,
  ) {
    final baseUrl = _extractBaseUrl(searchUrl);
    final roads = <Road>[];

    try {
      final epSelector = format.selectEpisodes;
      final linkSelector = format.selectEpisodeLinks;

      final epNodes =
          epSelector.isNotEmpty ? root.querySelectorAll(epSelector) : [];
      final linkNodes =
          linkSelector.isNotEmpty ? root.querySelectorAll(linkSelector) : [];

      final count =
          epNodes.length < linkNodes.length
              ? epNodes.length
              : linkNodes.length;

      final urls = <String>[];
      final names = <String>[];
      for (var i = 0; i < count; i++) {
        final href = linkNodes[i].attributes['href']?.trim() ?? '';
        if (href.isEmpty) continue;

        final epName = _cleanEpisodeName(epNodes[i].text, format.matchEpisodeSortFromName, i);

        urls.add(normalizeEpisodeUrl(baseUrl, href));
        names.add(epName);
      }

      if (urls.isNotEmpty) {
        roads.add(Road(name: '播放线路', data: urls, identifier: names));
      }
    } catch (e) {
      diagnostics.add('无频道剧集解析失败: $e');
    }

    return roads;
  }

  /// Fallback: just find all links on the page as a single playlist.
  List<Road> _fallbackEpisodeParse(
    Element root,
    String searchUrl,
    List<String> diagnostics,
  ) {
    final baseUrl = _extractBaseUrl(searchUrl);
    final urls = <String>[];
    final names = <String>[];

    try {
      final links = root.querySelectorAll('a[href]');
      for (var i = 0; i < links.length; i++) {
        final href = links[i].attributes['href']?.trim() ?? '';
        if (href.isEmpty) continue;
        // Skip external links
        if (href.startsWith('http') &&
            !href.contains(Uri.tryParse(baseUrl)?.host ?? '')) {
          continue;
        }
        final text = links[i].text.trim();
        if (text.isEmpty) continue;
        urls.add(normalizeEpisodeUrl(baseUrl, href));
        names.add(text);
      }
    } catch (e) {
      diagnostics.add('后备剧集解析失败: $e');
    }

    if (urls.isNotEmpty) {
      return [
        Road(name: '播放线路', data: urls, identifier: names),
      ];
    }
    return [];
  }

  // ------------------------------------------------------------------
  // Video URL extraction from playback page
  // ------------------------------------------------------------------

  /// Extracts the direct video URL from a playback page HTML.
  ///
  /// Returns the matched URL, or the original [pageUrl] if no match found.
  String extractVideoUrl(String pageHtml, AnimekoWebSelectorRule rule) {
    final matchVideo = rule.searchConfig.matchVideo;
    if (matchVideo.matchVideoUrl.isEmpty) return '';

    // 1. Try nested URL extraction first
    if (matchVideo.enableNestedUrl &&
        matchVideo.matchNestedUrl.isNotEmpty) {
      try {
        final nestedRegex = RegExp(matchVideo.matchNestedUrl,
            caseSensitive: false, dotAll: true);
        final nestedMatch = nestedRegex.firstMatch(pageHtml);
        if (nestedMatch != null) {
          String nestedUrl;
          if (nestedMatch.namedGroup('v') != null) {
            nestedUrl = nestedMatch.namedGroup('v')!;
          } else {
            nestedUrl = nestedMatch.group(0) ?? '';
          }
          // This would need recursive resolution, but for now return
          // the matched nested URL
          if (nestedUrl.isNotEmpty) return nestedUrl;
        }
      } catch (_) {}
    }

    // 2. Try direct video URL regex
    try {
      final videoRegex = RegExp(matchVideo.matchVideoUrl,
          caseSensitive: false, dotAll: true);
      final videoMatch = videoRegex.firstMatch(pageHtml);
      if (videoMatch != null) {
        if (videoMatch.namedGroup('v') != null) {
          return videoMatch.namedGroup('v')!;
        }
        return videoMatch.group(0) ?? '';
      }
    } catch (_) {}

    return '';
  }

  /// Builds HTTP headers for video playback requests.
  Map<String, String> buildVideoHeaders(AnimekoWebSelectorRule rule) {
    final headers = <String, String>{
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    };
    final matchVideo = rule.searchConfig.matchVideo;
    if (matchVideo.cookies.isNotEmpty) {
      headers['cookie'] = matchVideo.cookies;
    }
    for (final entry in matchVideo.addHeadersToVideo.entries) {
      if (entry.key.isNotEmpty) {
        headers[entry.key] = entry.value;
      }
    }
    // Set referer if empty string specified (use current domain)
    if (matchVideo.addHeadersToVideo.containsKey('referer') &&
        (matchVideo.addHeadersToVideo['referer']?.isEmpty ?? true)) {
      headers['referer'] = _extractBaseUrl(rule.searchConfig.searchUrl);
    }
    return headers;
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  Element _parseHtml(String raw) {
    try {
      final element = parse(raw).documentElement;
      if (element == null) {
        throw const CssRuleFormatException('HTML 响应没有根节点');
      }
      return element;
    } on CssRuleFormatException {
      rethrow;
    } catch (error) {
      throw CssRuleFormatException(
        'HTML 响应解析失败',
        cause: error,
      );
    }
  }

  /// Extracts the base URL (scheme + host) from a full URL.
  String _extractBaseUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return url;
    }
  }

  /// Cleans an episode name extracted from HTML.
  ///
  /// Strips icon glyphs/special chars, applies the [matchEpisodeSortFromName]
  /// regex if configured, and falls back to "第N集" format.
  String _cleanEpisodeName(
    String rawText,
    String matchEpisodeSortFromName,
    int index,
  ) {
    // 1. Strip zero-width characters and control chars
    var cleaned = rawText.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\u200B-\u200F\uFEFF\u00AD]'), '');
    
    // 2. Strip HTML entity remnants like &nbsp; &#x...;
    cleaned = cleaned.replaceAll(RegExp(r'&[a-z]+;'), ' ');
    
    // 3. Remove common icon placeholders (FontAwesome, SVG placeholders, etc)
    cleaned = cleaned.replaceAll(RegExp(r'||||||||-|-'), '');
    
    // 4. Collapse whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    if (cleaned.isEmpty) return '第${index + 1}集';

    // 5. Try matchEpisodeSortFromName regex
    if (matchEpisodeSortFromName.isNotEmpty) {
      try {
        final regex = RegExp(matchEpisodeSortFromName);
        final match = regex.firstMatch(cleaned);
        if (match != null && match.namedGroup('ep') != null) {
          return '第${match.namedGroup('ep')}集';
        }
      } catch (_) {}
    }

    // 6. Try generic patterns: "第X集", "第X话", "EP X", "X"
    final genericMatch = RegExp(r'(?:第\s*)?(?<ep>\d+)\s*[集话話话epEP]?').firstMatch(cleaned);
    if (genericMatch != null && genericMatch.namedGroup('ep') != null) {
      return '第${genericMatch.namedGroup('ep')}集';
    }

    // 7. Only return cleaned text if it looks like a valid episode name
    // (contains Chinese, digits, or common anime-related chars)
    if (RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf0-9a-zA-Z]').hasMatch(cleaned) &&
        cleaned.length <= 30) {
      return cleaned;
    }

    // 8. Final fallback
    return '第${index + 1}集';
  }
}

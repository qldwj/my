import 'package:html/parser.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

/// Exception thrown when RSS rule execution fails.
class RssRuleFormatException implements Exception {
  const RssRuleFormatException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'RssRuleFormatException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Strategy for executing Animeko RSS rules.
///
/// RSS rules return standard RSS/XML feeds containing magnet links.
/// This strategy fetches the RSS feed and extracts search results.
class RssRuleStrategy {
  const RssRuleStrategy();

  /// Prepares an RSS search request.
  PreparedRuleRequest prepareSearchRequest(
    String searchUrl,
    String keyword,
  ) {
    final url = searchUrl.replaceAll(
      RegExp(r'\{keyword\}', caseSensitive: false),
      Uri.encodeQueryComponent(keyword),
    );
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw RssRuleFormatException('RSS URL 无效: $url');
    }
    return PreparedRuleRequest(method: 'GET', url: url);
  }

  /// Parses RSS XML response into search results.
  ///
  /// Standard RSS item structure:
  /// ```xml
  /// <item>
  ///   <title>标题</title>
  ///   <link>页面链接</link>
  ///   <guid>唯一标识</guid>
  ///   <enclosure url="磁链/种子URL" type="application/x-bittorrent"/>
  ///   <description>描述</description>
  /// </item>
  /// ```
  RuleSearchParseResult parseSearch(String raw) {
    final diagnostics = <String>[];
    final items = <SearchItem>[];

    try {
      final document = parse(raw);
      final itemNodes = document.querySelectorAll('item');

      if (itemNodes.isEmpty) {
        // Try RSS v2 without wrapper
        throw RssRuleFormatException('RSS 中没有找到 item 元素');
      }

      for (var index = 0; index < itemNodes.length; index++) {
        try {
          final item = itemNodes[index];

          // Title
          final titleEl = item.querySelector('title');
          var name = titleEl?.text.trim() ?? '';
          if (name.isEmpty) continue;

          // Link (page URL)
          final linkEl = item.querySelector('link');
          final pageUrl = linkEl?.text.trim() ?? '';

          // Enclosure (magnet/torrent URL) - most important for BT resources
          final enclosureEl = item.querySelector('enclosure');
          final enclosureUrl = enclosureEl?.attributes['url']?.trim() ?? '';

          // Also check for alternate link formats
          final guidEl = item.querySelector('guid');
          final guid = guidEl?.text.trim() ?? '';

          // Store the most useful URL as source
          // Priority: enclosure > link > guid
          final src = enclosureUrl.isNotEmpty
              ? enclosureUrl
              : (pageUrl.isNotEmpty ? pageUrl : guid);

          if (src.isEmpty) continue;

          items.add(SearchItem(name: name, src: src));
        } catch (e) {
          diagnostics.add('RSS 条目 $index 解析失败: $e');
        }
      }
    } on RssRuleFormatException {
      rethrow;
    } catch (e) {
      diagnostics.add('RSS 解析失败: $e');
    }

    return RuleSearchParseResult(
      items: items,
      diagnostics: diagnostics,
    );
  }
}

/// Animeko web-selector rule configuration model.
///
/// Mirrors the `exportedMediaSourceDataList.mediaSources[].arguments` JSON
/// structure from Animeko so that Kazumi can load and execute the same rules.

/// Key used to store/retrieve the full Animeko rule config in a Plugin's
/// JSON serialization when running in CSS mode.
const String animekoConfigKey = 'animekoConfig';

class AnimekoMatchVideoConfig {
  final bool enableNestedUrl;
  final String matchNestedUrl;
  final String matchVideoUrl;
  final String cookies;
  final Map<String, String> addHeadersToVideo;

  AnimekoMatchVideoConfig({
    this.enableNestedUrl = true,
    this.matchNestedUrl = r'$^',
    this.matchVideoUrl = '',
    this.cookies = '',
    Map<String, String>? addHeadersToVideo,
  }) : addHeadersToVideo = addHeadersToVideo ?? const {};

  factory AnimekoMatchVideoConfig.fromJson(Map<String, dynamic> json) {
    return AnimekoMatchVideoConfig(
      enableNestedUrl: json['enableNestedUrl'] as bool? ?? true,
      matchNestedUrl: json['matchNestedUrl'] as String? ?? r'$^',
      matchVideoUrl: json['matchVideoUrl'] as String? ?? '',
      cookies: json['cookies'] as String? ?? '',
      addHeadersToVideo: json['addHeadersToVideo'] is Map
          ? Map<String, String>.from(json['addHeadersToVideo'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'enableNestedUrl': enableNestedUrl,
        'matchNestedUrl': matchNestedUrl,
        'matchVideoUrl': matchVideoUrl,
        if (cookies.isNotEmpty) 'cookies': cookies,
        if (addHeadersToVideo.isNotEmpty) 'addHeadersToVideo': addHeadersToVideo,
      };
}

class AnimekoSelectorSubjectFormatA {
  final String selectLists;
  final bool preferShorterName;

  AnimekoSelectorSubjectFormatA({
    this.selectLists = '',
    this.preferShorterName = true,
  });

  factory AnimekoSelectorSubjectFormatA.fromJson(Map<String, dynamic> json) {
    return AnimekoSelectorSubjectFormatA(
      selectLists: json['selectLists'] as String? ?? '',
      preferShorterName: json['preferShorterName'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'selectLists': selectLists,
        'preferShorterName': preferShorterName,
      };
}

class AnimekoSelectorSubjectFormatIndexed {
  final String selectNames;
  final String selectLinks;
  final bool preferShorterName;

  AnimekoSelectorSubjectFormatIndexed({
    this.selectNames = '',
    this.selectLinks = '',
    this.preferShorterName = true,
  });

  factory AnimekoSelectorSubjectFormatIndexed.fromJson(
      Map<String, dynamic> json) {
    return AnimekoSelectorSubjectFormatIndexed(
      selectNames: json['selectNames'] as String? ?? '',
      selectLinks: json['selectLinks'] as String? ?? '',
      preferShorterName: json['preferShorterName'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'selectNames': selectNames,
        'selectLinks': selectLinks,
        'preferShorterName': preferShorterName,
      };
}

class AnimekoSelectMedia {
  final bool distinguishSubjectName;
  final bool distinguishChannelName;

  AnimekoSelectMedia({
    this.distinguishSubjectName = true,
    this.distinguishChannelName = true,
  });

  factory AnimekoSelectMedia.fromJson(Map<String, dynamic> json) {
    return AnimekoSelectMedia(
      distinguishSubjectName:
          json['distinguishSubjectName'] as bool? ?? true,
      distinguishChannelName:
          json['distinguishChannelName'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'distinguishSubjectName': distinguishSubjectName,
        'distinguishChannelName': distinguishChannelName,
      };
}

class AnimekoSelectorChannelFormatFlattened {
  final String selectChannelNames;
  final String matchChannelName;
  final String selectEpisodeLists;
  final String selectEpisodesFromList;
  final String selectEpisodeLinksFromList;
  final String matchEpisodeSortFromName;

  AnimekoSelectorChannelFormatFlattened({
    this.selectChannelNames = '',
    this.matchChannelName = '',
    this.selectEpisodeLists = '',
    this.selectEpisodesFromList = '',
    this.selectEpisodeLinksFromList = '',
    this.matchEpisodeSortFromName = '',
  });

  factory AnimekoSelectorChannelFormatFlattened.fromJson(
      Map<String, dynamic> json) {
    return AnimekoSelectorChannelFormatFlattened(
      selectChannelNames: json['selectChannelNames'] as String? ?? '',
      matchChannelName: json['matchChannelName'] as String? ?? '',
      selectEpisodeLists: json['selectEpisodeLists'] as String? ?? '',
      selectEpisodesFromList: json['selectEpisodesFromList'] as String? ?? '',
      selectEpisodeLinksFromList:
          json['selectEpisodeLinksFromList'] as String? ?? '',
      matchEpisodeSortFromName:
          json['matchEpisodeSortFromName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'selectChannelNames': selectChannelNames,
        'matchChannelName': matchChannelName,
        'selectEpisodeLists': selectEpisodeLists,
        'selectEpisodesFromList': selectEpisodesFromList,
        'selectEpisodeLinksFromList': selectEpisodeLinksFromList,
        'matchEpisodeSortFromName': matchEpisodeSortFromName,
      };
}

class AnimekoSelectorChannelFormatNoChannel {
  final String selectEpisodes;
  final String selectEpisodeLinks;
  final String matchEpisodeSortFromName;

  AnimekoSelectorChannelFormatNoChannel({
    this.selectEpisodes = '',
    this.selectEpisodeLinks = '',
    this.matchEpisodeSortFromName = '',
  });

  factory AnimekoSelectorChannelFormatNoChannel.fromJson(
      Map<String, dynamic> json) {
    return AnimekoSelectorChannelFormatNoChannel(
      selectEpisodes: json['selectEpisodes'] as String? ?? '',
      selectEpisodeLinks: json['selectEpisodeLinks'] as String? ?? '',
      matchEpisodeSortFromName:
          json['matchEpisodeSortFromName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'selectEpisodes': selectEpisodes,
        'selectEpisodeLinks': selectEpisodeLinks,
        'matchEpisodeSortFromName': matchEpisodeSortFromName,
      };
}

class AnimekoSearchConfig {
  final String searchUrl;
  final bool searchUseOnlyFirstWord;
  final int? searchUseSubjectNamesCount;
  final int? requestInterval;
  final String subjectFormatId;
  final AnimekoSelectorSubjectFormatA? selectorSubjectFormatA;
  final AnimekoSelectorSubjectFormatIndexed? selectorSubjectFormatIndexed;
  final String channelFormatId;
  final AnimekoSelectorChannelFormatFlattened?
      selectorChannelFormatFlattened;
  final AnimekoSelectorChannelFormatNoChannel?
      selectorChannelFormatNoChannel;
  final String defaultResolution;
  final String defaultSubtitleLanguage;
  final List<String> onlySupportsPlayers;
  final bool filterBySubjectName;
  final AnimekoSelectMedia selectMedia;
  final AnimekoMatchVideoConfig matchVideo;

  AnimekoSearchConfig({
    this.searchUrl = '',
    this.searchUseOnlyFirstWord = true,
    this.searchUseSubjectNamesCount,
    this.requestInterval,
    this.subjectFormatId = 'a',
    this.selectorSubjectFormatA,
    this.selectorSubjectFormatIndexed,
    this.channelFormatId = 'index-grouped',
    this.selectorChannelFormatFlattened,
    this.selectorChannelFormatNoChannel,
    this.defaultResolution = '1080P',
    this.defaultSubtitleLanguage = 'CHS',
    List<String>? onlySupportsPlayers,
    this.filterBySubjectName = true,
    AnimekoSelectMedia? selectMedia,
    AnimekoMatchVideoConfig? matchVideo,
  })  : onlySupportsPlayers = onlySupportsPlayers ?? const [],
        selectMedia = selectMedia ?? AnimekoSelectMedia(),
        matchVideo = matchVideo ?? AnimekoMatchVideoConfig();

  factory AnimekoSearchConfig.fromJson(Map<String, dynamic> json) {
    return AnimekoSearchConfig(
      searchUrl: json['searchUrl'] as String? ?? '',
      searchUseOnlyFirstWord:
          json['searchUseOnlyFirstWord'] as bool? ?? true,
      searchUseSubjectNamesCount:
          json['searchUseSubjectNamesCount'] as int?,
      requestInterval: json['requestInterval'] as int?,
      subjectFormatId: json['subjectFormatId'] as String? ?? 'a',
      selectorSubjectFormatA: json['selectorSubjectFormatA'] is Map
          ? AnimekoSelectorSubjectFormatA.fromJson(
              Map<String, dynamic>.from(json['selectorSubjectFormatA']))
          : null,
      selectorSubjectFormatIndexed: json['selectorSubjectFormatIndexed'] is Map
          ? AnimekoSelectorSubjectFormatIndexed.fromJson(
              Map<String, dynamic>.from(json['selectorSubjectFormatIndexed']))
          : null,
      channelFormatId: json['channelFormatId'] as String? ?? 'index-grouped',
      selectorChannelFormatFlattened:
          json['selectorChannelFormatFlattened'] is Map
              ? AnimekoSelectorChannelFormatFlattened.fromJson(
                  Map<String, dynamic>.from(
                      json['selectorChannelFormatFlattened']))
              : null,
      selectorChannelFormatNoChannel:
          json['selectorChannelFormatNoChannel'] is Map
              ? AnimekoSelectorChannelFormatNoChannel.fromJson(
                  Map<String, dynamic>.from(
                      json['selectorChannelFormatNoChannel']))
              : null,
      defaultResolution: json['defaultResolution'] as String? ?? '1080P',
      defaultSubtitleLanguage:
          json['defaultSubtitleLanguage'] as String? ?? 'CHS',
      onlySupportsPlayers: json['onlySupportsPlayers'] is List
          ? List<String>.from(json['onlySupportsPlayers'] as List)
          : const [],
      filterBySubjectName: json['filterBySubjectName'] as bool? ?? true,
      selectMedia: json['selectMedia'] is Map
          ? AnimekoSelectMedia.fromJson(
              Map<String, dynamic>.from(json['selectMedia']))
          : AnimekoSelectMedia(),
      matchVideo: json['matchVideo'] is Map
          ? AnimekoMatchVideoConfig.fromJson(
              Map<String, dynamic>.from(json['matchVideo']))
          : AnimekoMatchVideoConfig(),
    );
  }

  Map<String, dynamic> toJson() => {
        'searchUrl': searchUrl,
        'searchUseOnlyFirstWord': searchUseOnlyFirstWord,
        if (searchUseSubjectNamesCount != null)
          'searchUseSubjectNamesCount': searchUseSubjectNamesCount,
        if (requestInterval != null) 'requestInterval': requestInterval,
        'subjectFormatId': subjectFormatId,
        if (selectorSubjectFormatA != null)
          'selectorSubjectFormatA': selectorSubjectFormatA!.toJson(),
        if (selectorSubjectFormatIndexed != null)
          'selectorSubjectFormatIndexed': selectorSubjectFormatIndexed!.toJson(),
        'channelFormatId': channelFormatId,
        if (selectorChannelFormatFlattened != null)
          'selectorChannelFormatFlattened':
              selectorChannelFormatFlattened!.toJson(),
        if (selectorChannelFormatNoChannel != null)
          'selectorChannelFormatNoChannel':
              selectorChannelFormatNoChannel!.toJson(),
        'defaultResolution': defaultResolution,
        'defaultSubtitleLanguage': defaultSubtitleLanguage,
        'onlySupportsPlayers': onlySupportsPlayers,
        'filterBySubjectName': filterBySubjectName,
        'selectMedia': selectMedia.toJson(),
        'matchVideo': matchVideo.toJson(),
      };
}

class AnimekoWebSelectorRule {
  final String name;
  final String description;
  final String iconUrl;
  final AnimekoSearchConfig searchConfig;
  final int tier;

  AnimekoWebSelectorRule({
    required this.name,
    this.description = '',
    this.iconUrl = '',
    required this.searchConfig,
    this.tier = 3,
  });

  factory AnimekoWebSelectorRule.fromJson(Map<String, dynamic> json) {
    return AnimekoWebSelectorRule(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      iconUrl: json['iconUrl'] as String? ?? '',
      searchConfig: json['searchConfig'] is Map
          ? AnimekoSearchConfig.fromJson(
              Map<String, dynamic>.from(json['searchConfig']))
          : AnimekoSearchConfig(),
      tier: json['tier'] as int? ?? 3,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'iconUrl': iconUrl,
        'searchConfig': searchConfig.toJson(),
        'tier': tier,
      };
}

/// Full Animeko media source entry, wrapping a web-selector or rss rule.
class AnimekoMediaSource {
  final String factoryId;
  final int version;
  final AnimekoWebSelectorRule? webSelectorArguments;
  // RSS rules are handled separately by Kazumi's existing RSS support.

  AnimekoMediaSource({
    required this.factoryId,
    this.version = 2,
    this.webSelectorArguments,
  });

  factory AnimekoMediaSource.fromJson(Map<String, dynamic> json) {
    return AnimekoMediaSource(
      factoryId: json['factoryId'] as String? ?? 'web-selector',
      version: json['version'] as int? ?? 2,
      webSelectorArguments: json['arguments'] is Map
          ? AnimekoWebSelectorRule.fromJson(
              Map<String, dynamic>.from(json['arguments']))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'factoryId': factoryId,
        'version': version,
        if (webSelectorArguments != null)
          'arguments': webSelectorArguments!.toJson(),
      };
}

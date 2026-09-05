import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/utils/date_time.dart';
import 'bangumi_interest.dart';

part 'bangumi_item.g.dart';

@HiveType(typeId: 0)
class BangumiItem {
  @HiveField(0)
  int id;
  @HiveField(1)
  int type;
  @HiveField(2)
  String name;
  @HiveField(3)
  String nameCn;
  @HiveField(4)
  String summary;
  @HiveField(5)
  String airDate;
  @HiveField(6)
  int airWeekday;
  @HiveField(7)
  int rank;
  @HiveField(8)
  Map<String, String> images;
  @HiveField(9, defaultValue: [])
  List<BangumiTag> tags;
  @HiveField(10, defaultValue: [])
  List<String> alias;
  @HiveField(11, defaultValue: 0.0)
  double ratingScore;
  @HiveField(12, defaultValue: 0)
  int votes;
  @HiveField(13, defaultValue: [])
  List<int> votesCount;
  @HiveField(14, defaultValue: '')
  String info;
  BangumiInterest? interest;

  // ==================== 新增：详情页展示用的集数/状态 ====================
  /// 0 = 未开播 / UPCOMING, 1 = 连载中 / ON_AIR, 2 = 完结 / COMPLETED
  @HiveField(15, defaultValue: 0)
  int status;
  /// 总话数（主线剧集数）
  @HiveField(16, defaultValue: 0)
  int totalEpisodes;
  /// 最近更新到第几话（为 0 时表示未播出）
  @HiveField(17, defaultValue: 0)
  int latestEpisode;
  // ====================

  BangumiItem({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.airDate,
    required this.airWeekday,
    required this.rank,
    required this.images,
    required this.tags,
    required this.alias,
    required this.ratingScore,
    required this.votes,
    required this.votesCount,
    required this.info,
    this.interest,
    this.status = 0,
    this.totalEpisodes = 0,
    this.latestEpisode = 0,
  });

  factory BangumiItem.fromJson(Map<String, dynamic> json) {
    List<String> parseBangumiAliases(Map<String, dynamic> jsonData) {
      if (jsonData.containsKey('infobox') && jsonData['infobox'] is List) {
        final List<dynamic> infobox = jsonData['infobox'];
        for (var item in infobox) {
          if (item is Map && item['key'] == '别名') {
            // api.bgm.tv /v0 uses `value`; next.bgm.tv /p1 uses `values`
            final dynamic raw = item['values'] ?? item['value'];
            if (raw == null) {
              return [];
            }
            if (raw is List) {
              return raw
                  .map<String>((element) {
                    if (element is Map && element.containsKey('v')) {
                      return element['v'].toString();
                    }
                    return element.toString().trim();
                  })
                  .where((alias) => alias.isNotEmpty)
                  .toList();
            }
            final text = raw.toString().trim();
            return text.isEmpty ? [] : [text];
          }
        }
      }
      return [];
    }

    List<int> parseBangumiVoteCount(Map<String, dynamic> jsonData) {
      if (!jsonData.containsKey('rating')) {
        return [];
      }
      final json = jsonData['rating']['count'];
      // For api.bgm.tv
      if (json is Map<String, dynamic>) {
        return List<int>.generate(10, (i) => json['${i + 1}'] as int);
      }
      // For next.bgm.tv
      if (json is List<dynamic>) {
        return json.map((e) => e as int).toList();
      }
      return [];
    }

    String resolveAirDateString(Map<String, dynamic> jsonData) {
      String? nonEmpty(dynamic v) {
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }
      // For api.bgm.tv date
      final fromTop = nonEmpty(jsonData['date']);
      if (fromTop != null) return fromTop;
      // For next.bgm.tv date
      final airtime = jsonData['airtime'];
      if (airtime is Map) {
        final fromAir = nonEmpty(airtime['date']);
        if (fromAir != null) return fromAir;
      }
      return '';
    }

    final String airDateStr = resolveAirDateString(json);

    List list = json['tags'] ?? [];
    List<String> bangumiAlias = parseBangumiAliases(json);
    List<BangumiTag> tagList = list.map((i) => BangumiTag.fromJson(i)).toList();
    List<int> voteList = parseBangumiVoteCount(json);
    BangumiInterest? interest;
    final interestRaw = json['interest'];
    if (interestRaw is Map<String, dynamic>) {
      interest = BangumiInterest.fromJson(json['interest']);
    } else if (interestRaw is Map) {
      interest = BangumiInterest.fromJson(Map<String, dynamic>.from(interestRaw));
    }
    return BangumiItem(
      id: json['id'],
      type: json['type'] ?? 2,
      name: json['name'] ?? '',
      nameCn: (json['name_cn'] ?? '') == ''
          ? (((json['nameCN'] ?? '') == '') ? json['name'] : json['nameCN'])
          : json['name_cn'],
      summary: json['summary'] ?? '',
      airDate: airDateStr,
      airWeekday: dateStringToWeekday(airDateStr.isEmpty ? '2000-11-11' : airDateStr),
      rank: json['rating']['rank'] ?? 0,
      images: Map<String, String>.from(
        json['images'] ??
            {
              "large": json['image'],
              "common": "",
              "medium": "",
              "small": "",
              "grid": ""
            },
      ),
      tags: tagList,
      alias: bangumiAlias,
      ratingScore: double.parse(
          (json['rating']['score'] ?? 0.0).toDouble().toStringAsFixed(1)),
      votes: json['rating']['total'] ?? 0,
      votesCount: voteList,
      info: json['info'] ?? '',
      // 集数/播出状态：api.bgm.tv /v0 与 next.bgm.tv /p1 均有 eps 与 status 字段
      totalEpisodes: (json['eps'] is num) ? (json['eps'] as num).toInt() : 0,
      status: _parseAiringStatus(json['status'], airDateStr),
      interest: interest,
    );
  }

  /// 把 Bangumi 的 status 字段映射为本地位：
  /// 0=未开播(UPCOMING), 1=连载中(ON_AIR), 2=已完结(COMPLETED)
  ///
  /// 与 Ani 的 SubjectAiringInfo.computeFromSubjectInfo 逻辑一致：
  /// completeDate 有效 => COMPLETED；airDate 在过去 => ON_AIR；否则 UPCOMING。
  /// Bangumi status 取值：airing(连载中) / finished(完结) / na(未放送)。
  static int _parseAiringStatus(dynamic statusRaw, String airDateStr) {
    final s = statusRaw?.toString() ?? '';
    switch (s) {
      case 'airing':
        return 1;
      case 'finished':
        return 2;
      case 'na':
      default:
        // na：按首播日期推断（Ani 同款推断）
        if (airDateStr.isNotEmpty) {
          final d = DateTime.tryParse(airDateStr);
          if (d != null) {
            final now = DateTime.now();
            if (d.isBefore(now)) return 1; // 已开播且未标完结 => 连载中
            return 0; // 未开播
      }
    }
    return 0;
  }
}
  }

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';

/// 未成年人保护模式过滤器
/// 开启时过滤掉 卖肉/里番/18+ 内容
class NsfwFilter {
  static const _nsfwKeywords = [
    '18禁', 'R18', 'R-18', '成人', '限制级',
    '卖肉', '里番', '肉番', '后宫', 'harem', 'ecchi', 'エッチ',
    'エロ', 'アダルト', 'hentai',
    '裸', '露出', ' erotic', 'sex',
  ];

  static const _nsfwTagIds = [
    'R18', '18禁', '限制级', '成人向け', '卖肉',
    '里番', '肉番', 'エロ', 'R-18',
  ];

  static bool get isEnabled => GStorage.getSetting(SettingsKeys.minorMode);

  static bool isNsfw(BangumiItem item) {
    if (!isEnabled) return false;
    final title = '${item.name} ${item.nameCn}'.toLowerCase();
    for (final kw in _nsfwKeywords) {
      if (title.contains(kw.toLowerCase())) return true;
    }
    for (final tag in item.tags) {
      if (_nsfwTagIds.any((n) => tag.name.toLowerCase().contains(n.toLowerCase()))) return true;
    }
    for (final alias in item.alias) {
      if (_nsfwKeywords.any((kw) => alias.toLowerCase().contains(kw.toLowerCase()))) return true;
    }
    return false;
  }

  static List<BangumiItem> filter(List<BangumiItem> items) {
    if (!isEnabled) return items;
    return items.where((item) => !isNsfw(item)).toList();
  }
}

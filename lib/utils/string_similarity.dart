// 计算两个字符串的编辑距离, 曾用于弹幕标题匹配
// 由于 DanDanPlay 现在直接提供基于 bgmBangumiID 的弹幕反查，此方法已不再使用

import 'dart:math';

int levenshteinDistance(String s1, String s2) {
  if (s1 == s2) return 0;
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;

  List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(s2.length + 1, 0);

  for (int i = 0; i < s1.length; i++) {
    v1[0] = i + 1;

    for (int j = 0; j < s2.length; j++) {
      int cost = (s1[i] == s2[j]) ? 0 : 1;
      v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
    }

    for (int j = 0; j < v0.length; j++) {
      v0[j] = v1[j];
    }
  }

  return v1[s2.length];
}

// 计算相似度百分比
double calculateSimilarity(String s1, String s2) {
  int maxLength = max(s1.length, s2.length);
  if (maxLength == 0) return 1.0;
  if (s1 == s2) return 1.0;
  return (1.0 - levenshteinDistance(s1, s2) / maxLength);
}

/// 🆕 番剧名匹配度评分（0~100），用于「选源 / 选搜索结果」时帮用户挑最准的。
///
/// 规则（对用户直觉友好，而非纯编辑距离）：
/// - 完全相等（忽略大小写/空白/常见标点）        → 100
/// - 一方是另一方的子串（如「葬送的芙莉莲」⊂「葬送的芙莉莲 第二季」）
///   → 90 起步，越接近长度越接近 100
/// - 前缀相同（如「葬送的芙莉莲」vs「葬送的芙莉莲们」）→ 80~95
/// - 字符重合率（词元/汉字交集占较长串比例）      → 0~85
/// - 命中别名（keyword 的任一别名能匹配上）额外加权
///
/// [titles] 为番剧的多个候选名（中文名 / 原名 / 别名），取其中最高分。
int matchScorePercent({
  required List<String> titles,
  required String target,
}) {
  if (titles.isEmpty || target.trim().isEmpty) return 0;
  var best = 0;
  for (final t in titles) {
    final s = _scoreOne(t, target);
    if (s > best) best = s;
  }
  return best.clamp(0, 100);
}

/// 归一化：去掉空白、常见分隔符与标点，统一小写。
String _normalize(String s) {
  var r = s.toLowerCase();
  r = r.replaceAll(
      RegExp(r"""[\s\-_:：·・,，.。!！?？~～"“”'‘’()（）\[\]【】]"""), '');
  return r;
}

int _scoreOne(String a, String b) {
  final x = _normalize(a);
  final y = _normalize(b);
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 100;

  final shorter = x.length <= y.length ? x : y;
  final longer = x.length <= y.length ? y : x;

  // 子串包含：长度越接近越长越可信
  if (longer.contains(shorter)) {
    final ratio = shorter.length / longer.length;
    // 90 ~ 100（长度比 >= 0.6 时基本接近满分）
    return (88 + (ratio * 12)).round().clamp(88, 99);
  }

  // 公共前缀
  var prefix = 0;
  while (prefix < shorter.length && x[prefix] == y[prefix]) {
    prefix++;
  }
  if (prefix >= 2 && prefix >= (shorter.length * 0.5)) {
    final ratio = prefix / longer.length;
    return (70 + ratio * 25).round().clamp(70, 95);
  }

  // 字符重合率（按字符集合交集 / 较长串长度）
  final setA = x.split('').toSet();
  final setB = y.split('').toSet();
  final inter = setA.intersection(setB).length;
  final union = setA.union(setB).length;
  final jaccard = union == 0 ? 0.0 : inter / union;
  // 再混一点编辑距离相似度，避免只看字符集合
  final edit = calculateSimilarity(x, y);
  final mixed = jaccard * 0.6 + edit * 0.4;
  return (mixed * 85).round().clamp(0, 85);
}

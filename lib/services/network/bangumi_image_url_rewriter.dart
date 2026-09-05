import 'package:kazumi/request/config/api_endpoints.dart';

/// Bangumi 图片 URL 重写器
///
/// 职责：
/// 1. 归一化：协议相对地址（//lain.bgm.tv/...）补全 https、http 强制转 https
/// 2. 镜像开启时，把 lain.bgm.tv 图片地址重写为图片代理地址
class BangumiImageUrlRewriter {
  BangumiImageUrlRewriter._();

  /// Bangumi 相关图片 host（lain.bgm.tv / bgm.tv / next.bgm.tv / kazumi.fyi）
  static bool _isBangumiHost(String host) {
    return host == 'bgm.tv' ||
        host.endsWith('.bgm.tv') ||
        host.endsWith('.kazumi.fyi');
  }

  /// 重写 Bangumi 图片地址
  ///
  /// [url]：原始图片地址
  /// [enabled]：是否走图片代理（镜像开关）
  static String rewrite(String url, {required bool enabled}) {
    // 协议相对地址补全
    var normalized = url;
    if (normalized.startsWith('//')) {
      normalized = 'https:$normalized';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null) return url;
    if (!_isBangumiHost(uri.host)) return normalized;

    // 强制 https（Bangumi 支持 https）
    final secureUrl = 'https://' +
        uri.host +
        uri.path +
        (uri.hasQuery ? '?${uri.query}' : '');

    if (!enabled) return secureUrl;

    // 走图片代理
    return '${ApiEndpoints.bangumiImageProxyBase}${Uri.encodeComponent(secureUrl)}';
  }
}

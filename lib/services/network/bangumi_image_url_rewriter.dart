import 'package:kazumi/request/config/api_endpoints.dart';

/// Bangumi 图片 URL 重写器
///
/// 职责：
/// 1. 归一化：协议相对地址（//lain.bgm.tv/...）补全 https、http 强制转 https
/// 2. 镜像开启时，把 Bangumi 图片地址重写为图片代理地址（wsrv.nl）
///
/// 官方 2.3.6 适配：新增 Uri 版 rewrite / isBangumiImage，供新的
/// 图片加速管线（ECH/镜像/直连）使用；旧的 String 版 rewrite 保留，
/// 兼容 bangumi_avatar 等现有调用。
abstract final class BangumiImageUrlRewriter {
  BangumiImageUrlRewriter._();

  static const _apiImageKinds = {'subjects', 'characters', 'persons'};

  /// Bangumi 相关图片 host（lain.bgm.tv / bgm.tv / next.bgm.tv / kazumi.fyi）
  static bool _isBangumiHost(String host) {
    return host == 'bgm.tv' ||
        host.endsWith('.bgm.tv') ||
        host.endsWith('.kazumi.fyi');
  }

  static bool _isHttp(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

  /// 是否为 Bangumi 图片地址（ECH 加速 / 镜像只处理这些地址）
  static bool isBangumiImage(Uri uri) =>
      _isHttp(uri) && (uri.host == 'lain.bgm.tv' || _isApiImage(uri));

  static bool _isApiImage(Uri uri) {
    if (uri.host != 'api.bgm.tv') return false;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return false;
    return _apiImageKinds.contains(segments.first);
  }

  /// 镜像重写（Uri 版，给新的图片缓存管线使用）
  static Uri rewrite(Uri uri) {
    if (!isBangumiImage(uri)) return uri;

    final secureUrl = 'https://' +
        uri.host +
        uri.path +
        (uri.hasQuery ? '?${uri.query}' : '');

    return Uri.parse(
        '${ApiEndpoints.bangumiImageProxyBase}${Uri.encodeComponent(secureUrl)}');
  }

  /// 重写 Bangumi 图片地址（String 版，兼容旧调用）
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

import 'package:flutter/material.dart';
import 'package:yhdm/bean/card/network_img_layer.dart';
import 'package:yhdm/services/network/bangumi_image_url_rewriter.dart';

/// Bangumi 头像/网格图组件
///
/// 统一加载 Bangumi 图片：
/// - 头像【始终走图片代理】（无论镜像开关是否开启，保证能加载）
/// - 支持动态 GIF
/// - 空地址/加载失败时显示占位头像
///
/// 兼容两种构造参数：
/// - my 自定义：[url]（可空地址）+ [size]（边长，默认 40）
/// - 官方 2.3.7：[imageUrl] + [radius]（圆形半径，内部换算为边长）
class BangumiAvatar extends StatelessWidget {
  const BangumiAvatar({
    super.key,
    String? url,
    String? imageUrl,
    this.size = 40,
    double? radius,
  }) : url = imageUrl ?? url,
       _radius = radius;

  /// 图片地址（可空）
  final String? url;

  /// 边长（默认 40，圆形头像）
  final double size;

  /// 官方兼容参数：圆形半径；非空时边长取 radius*2
  final double? _radius;

  @override
  Widget build(BuildContext context) {
    final side = _radius != null ? _radius! * 2 : size;
    final src = (url == null || url!.isEmpty)
        ? 'https://bangumi.tv/img/info_only.png'
        : url!;
    // 头像始终走图片代理（enabled: true，不受镜像开关影响）
    return NetworkImgLayer(
      src: BangumiImageUrlRewriter.rewriteString(src, enabled: true),
      width: side,
      height: side,
      type: 'avatar',
    );
  }
}

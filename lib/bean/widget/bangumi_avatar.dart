import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/services/network/bangumi_image_url_rewriter.dart';

/// Bangumi 头像/网格图组件
///
/// 统一加载 Bangumi 图片：
/// - 头像【始终走图片代理】（无论镜像开关是否开启，保证能加载）
/// - 支持动态 GIF
/// - 空地址/加载失败时显示占位头像
class BangumiAvatar extends StatelessWidget {
  const BangumiAvatar({
    super.key,
    this.url,
    this.size = 40,
  });

  /// 图片地址（可空）
  final String? url;

  /// 边长（默认 40，圆形头像）
  final double size;

  @override
  Widget build(BuildContext context) {
    final src = (url == null || url!.isEmpty)
        ? 'https://bangumi.tv/img/info_only.png'
        : url!;
    // 头像始终走图片代理（enabled: true，不受镜像开关影响）
    return NetworkImgLayer(
      src: BangumiImageUrlRewriter.rewrite(src, enabled: true),
      width: size,
      height: size,
      type: 'avatar',
    );
  }
}

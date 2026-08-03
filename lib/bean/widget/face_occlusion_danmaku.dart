import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/services/player/face_occlusion_service.dart';

/// 弹幕防挡人脸裁剪层（类似 B 站）
///
/// 监听 [FaceOcclusionService] 的人脸检测结果，
/// 把弹幕画布裁剪成"视频区域减去人脸区域"（evenOdd 挖洞），
/// 弹幕滚到人脸处被隐藏、越过人脸后重新出现，形成从人脸后面穿过的效果。
class FaceOcclusionDanmaku extends StatelessWidget {
  const FaceOcclusionDanmaku({
    super.key,
    required this.data,
    required this.child,
  });

  final ValueListenable<FaceOcclusionData> data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FaceOcclusionData>(
      valueListenable: data,
      builder: (context, value, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final area = Size(constraints.maxWidth, constraints.maxHeight);
            final frame = value.frameSize;

            // 视频在弹幕区域内的实际显示区域（contain 适配、居中）
            final scale = (frame.width <= 0 || frame.height <= 0)
                ? 1.0
                : math.min(
                    area.width / frame.width,
                    area.height / frame.height,
                  );
            final videoW = frame.width * scale;
            final videoH = frame.height * scale;
            final videoRect = Rect.fromLTWH(
              (area.width - videoW) / 2,
              (area.height - videoH) / 2,
              videoW,
              videoH,
            );

            return ClipPath(
              clipper: _FaceOcclusionClipper(
                videoRect: videoRect,
                faces: value.faceRects,
              ),
              child: child,
            );
          },
        );
      },
    );
  }
}

class _FaceOcclusionClipper extends CustomClipper<Path> {
  const _FaceOcclusionClipper({
    required this.videoRect,
    required this.faces,
  });

  final Rect videoRect;
  final List<Rect> faces; // 归一化坐标（0~1）

  @override
  Path getClip(Size size) {
    final path = Path()..addRect(videoRect);
    for (final f in faces) {
      path.addRect(
        Rect.fromLTWH(
          videoRect.left + f.left * videoRect.width,
          videoRect.top + f.top * videoRect.height,
          f.width * videoRect.width,
          f.height * videoRect.height,
        ),
      );
    }
    return path..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(covariant _FaceOcclusionClipper oldClipper) {
    return oldClipper.videoRect != videoRect || oldClipper.faces != faces;
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:kazumi/services/logging/logger.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// 人脸检测结果
///
/// [frameSize]：视频帧原始尺寸（像素）
/// [faceRects]：归一化人脸矩形（0~1 坐标，相对视频帧）
class FaceOcclusionData {
  const FaceOcclusionData({
    required this.frameSize,
    required this.faceRects,
  });

  final Size frameSize;
  final List<Rect> faceRects;

  bool get isEmpty => faceRects.isEmpty;
}

/// 弹幕防挡人脸服务（类似 B 站）
///
/// 周期性截取视频帧 → ML Kit 人脸检测 → 输出人脸矩形。
/// 播放器拿到结果后在弹幕画布上把"人脸区域"挖掉，
/// 弹幕滚到人脸处被裁剪隐藏、越过人脸后重新出现，
/// 形成"弹幕从人脸后面穿过"的效果。
class FaceOcclusionService {
  Player? _player;
  FaceDetector? _detector;
  Timer? _timer;
  bool _disposed = false;

  /// 最新检测结果（播放器监听此值刷新弹幕裁剪）
  final ValueNotifier<FaceOcclusionData> data = ValueNotifier(
    const FaceOcclusionData(
      frameSize: Size(1920, 1080),
      faceRects: [],
    ),
  );

  bool get isRunning => _timer != null;

  /// 开始周期检测（约 0.8s 一次）
  Future<void> start(Player player) async {
    _player = player;
    if (_timer != null) return;
    try {
      _detector ??= FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableContours: false,
          enableLandmarks: false,
          enableClassification: false,
          enableTracking: false,
          minFaceSize: 0.08,
        ),
      );
      _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
        _detectOnce();
      });
    } catch (e) {
      KazumiLogger().e('FaceOcclusion: 初始化失败', error: e);
    }
  }

  Future<void> _detectOnce() async {
    final player = _player;
    if (player == null || _disposed) return;
    try {
      final raw = await player.screenshot(format: 'image/jpeg');
      if (raw == null || raw.isEmpty || _disposed) return;

      final file = await _writeTempJpeg(raw);
      if (file == null || _disposed) return;

      final input = InputImage.fromFilePath(file.path);
      final faces = await _detector?.processImage(input) ?? [];
      final size = await _readJpegSize(file);
      if (_disposed) return;

      final rects = <Rect>[];
      for (final f in faces) {
        final b = f.boundingBox;
        if (size.width <= 0 || size.height <= 0) continue;
        rects.add(
          Rect.fromLTWH(
            (b.left / size.width).clamp(0.0, 1.0),
            (b.top / size.height).clamp(0.0, 1.0),
            (b.width / size.width).clamp(0.0, 1.0),
            (b.height / size.height).clamp(0.0, 1.0),
          ),
        );
      }
      data.value = FaceOcclusionData(frameSize: size, faceRects: rects);
    } catch (e) {
      // 单次检测失败忽略，不影响整体
    }
  }

  Future<File?> _writeTempJpeg(Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/face_occlusion_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      KazumiLogger().e('FaceOcclusion: 写入临时文件失败', error: e);
      return null;
    }
  }

  Future<Size> _readJpegSize(File file) async {
    try {
      final decoded = img.decodeJpg(await file.readAsBytes());
      if (decoded != null && decoded.width > 0 && decoded.height > 0) {
        return Size(
          decoded.width.toDouble(),
          decoded.height.toDouble(),
        );
      }
    } catch (_) {}
    return const Size(1920, 1080);
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    data.value = const FaceOcclusionData(
      frameSize: Size(1920, 1080),
      faceRects: [],
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    try {
      await _detector?.close();
    } catch (_) {}
    _detector = null;
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/bangumi/bangumi_item.dart';
import 'package:kazumi/request/api/bangumi_api.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._internal();
  DeepLinkService._internal();

  MethodChannel channel = const MethodChannel('com.predidit.yhdm/deep_link');

  Future<void> init() async {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'receiveLink':
          final String url = call.arguments['url'];
          Uri? uri = Uri.tryParse(url);
          if (uri != null) {
            unawaited(_handleLink(uri));
          }
          break;
      }
    });
  }

  Future<void> _handleLink(Uri uri) async {
    debugPrint("DeepLink 接收链接：$uri");
    // 匹配 share/anime?id=xxx
    if (uri.pathSegments.length >= 2 &&
        uri.pathSegments[0] == 'share' &&
        uri.pathSegments[1] == 'anime') {
      final aidStr = uri.queryParameters['id'];
      if (aidStr != null) {
        final aid = int.tryParse(aidStr);
        if (aid != null) {
          // 固定等待3秒
          await Future.delayed(const Duration(seconds: 3));
          unawaited(_openAnimeDetail(aid));
        }
      }
      return;
    }
  }

  Future<void> _openAnimeDetail(int id) async {
    try {
      final item = await BangumiApi().getBangumiInfoByID(id);
      if (item == null) {
        debugPrint("DeepLink：未找到该番剧 $id");
        return;
      }
      if (rootNavigatorKey.currentContext == null) {
        debugPrint("DeepLink：页面尚未初始化完成");
        return;
      }
      Navigator.of(rootNavigatorKey.currentContext!)
          .pushNamed('/info/', arguments: item);
    } catch (e) {
      debugPrint("DeepLink 异常：$e");
    }
  }
}

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_logger_interceptor.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/http_headers.dart';

class DioFactory {
  DioFactory._();

  static Dio? _apiDio;
  static Dio? _rulesRepoDio;
  static Dio? _pluginDio;
  static Dio? _downloadDio;

  static Dio get apiDio => _apiDio ??= _create(
        NetworkConfig.fromSettings(),
        defaultHeaders: {
          'referer': '',
          'user-agent': getRandomUA(),
        },
        interceptors: [_BangumiMirrorInterceptor()],
      );

  static Dio get rulesRepoDio => _rulesRepoDio ??= _create(
        NetworkConfig.fromSettings(),
        defaultHeaders: {
          'user-agent': getRandomUA(),
        },
        interceptors: [_RulesMirrorInterceptor()],
      );

  static Dio get pluginDio => _pluginDio ??= _create(
        NetworkConfig.fromSettings(),
        defaultHeaders: {
          'user-agent': getRandomUA(),
          'accept-language': getRandomAcceptedLanguage(),
        },
      );

  static Dio get downloadDio => _downloadDio ??= _create(
        NetworkConfig.fromSettings(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
        defaultHeaders: {
          'user-agent': getRandomUA(),
        },
      );

  static Dio createForConfig(NetworkConfig config) {
    return _create(config);
  }

  static void reset() {
    _apiDio = null;
    _rulesRepoDio = null;
    _pluginDio = null;
    _downloadDio = null;
  }

  static Dio _create(
    NetworkConfig config, {
    Map<String, dynamic> defaultHeaders = const {},
    List<Interceptor> interceptors = const [],
  }) {
    // Keep the constructor tear-off form so the migration guard can flag
    // direct Dio construction outside this factory with a simple search.
    // ignore: unnecessary_constructor_name
    final dio = Dio.new(
      BaseOptions(
        connectTimeout: config.connectTimeout,
        receiveTimeout: config.receiveTimeout,
        sendTimeout: config.sendTimeout,
        headers: defaultHeaders,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    dio.httpClientAdapter = config.createAdapter();
    dio.transformer = BackgroundTransformer();
    dio.interceptors.addAll(interceptors);
    if (config.enableLog) {
      dio.interceptors.add(DioLoggerInterceptor());
    }
    return dio;
  }
}

class _BangumiMirrorInterceptor extends Interceptor {
  static const _mirrorableHosts = {
    'api.bgm.tv',
    'next.bgm.tv',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final enableBangumiProxy =
        GStorage.getSetting(SettingsKeys.enableBangumiProxy);
    if (!enableBangumiProxy) {
      handler.next(options);
      return;
    }

    final uri = options.uri;
    if (!_mirrorableHosts.contains(uri.host)) {
      handler.next(options);
      return;
    }

    final mirrored = ApiEndpoints.bangumiMirrorDomain +
        uri.path +
        (uri.hasQuery ? '?${uri.query}' : '');
    KazumiLogger().d('Bangumi mirror: $mirrored');
    options.path = mirrored;
    handler.next(options);
  }
}

class _RulesMirrorInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final enableGitProxy = GStorage.getSetting(SettingsKeys.enableGitProxy);
    if (!enableGitProxy) {
      handler.next(options);
      return;
    }

    final url = options.uri.toString();
    if (!url.startsWith(ApiEndpoints.pluginShop)) {
      handler.next(options);
      return;
    }

    final mirrored = ApiEndpoints.pluginShopMirror +
        url.substring(ApiEndpoints.pluginShop.length);
    KazumiLogger().d('Rules mirror: $mirrored');
    options.path = mirrored;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 兼容 GitCode contents API 的 {"content":"<base64>","encoding":"base64"} 包装：
    // 仅当路径是 /contents/ 时尝试透明解码；AtomGit raw API 直接返回原文，不受影响。
    final url = response.requestOptions.uri.toString();
    if (url.contains('/api/v5/repos/') &&
        url.contains('/contents/') &&
        response.data is String) {
      final trimmed = (response.data as String).trim();
      if (trimmed.startsWith('{')) {
        try {
          final obj = json.decode(trimmed);
          if (obj is Map && obj['content'] is String) {
            final b64 =
                (obj['content'] as String).replaceAll(RegExp(r'\s'), '');
            response.data =
                utf8.decode(base64.decode(base64.normalize(b64)));
          }
        } catch (_) {
          // 非 GitCode 包装（例如规则 JSON 本身），保持原样
        }
      }
    }
    handler.next(response);
  }
}

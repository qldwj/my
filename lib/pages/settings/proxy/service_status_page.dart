import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/utils/http_headers.dart';

/// 代理/服务状态检测页
class ServiceStatusPage extends StatefulWidget {
  const ServiceStatusPage({super.key});

  @override
  State<ServiceStatusPage> createState() => _ServiceStatusPageState();
}

class _ServiceStatusPageState extends State<ServiceStatusPage> {
  final List<_ServiceStatus> _services = [
    _ServiceStatus(
      name: 'Bangumi',
      desc: '收藏数据服务',
      url: 'https://api.qlyyz.top/kazumi/v1/popular/subjects?limit=1',
      avatar: null,
      checkType: ServiceCheckType.bangumiCollection,
    ),
    _ServiceStatus(
      name: 'Bangumi',
      desc: '评论服务',
      url: 'https://qlyyz.xyz/ping?pl',
      avatar: null,
      checkType: ServiceCheckType.bangumiComment,
    ),
    _ServiceStatus(
      name: '樱花动漫',
      desc: '弹幕,评论服务',
      url: 'https://qlyyz.xyz/ping',
      avatar: 'https://qlyyz.xyz/logo.webp',
      checkType: ServiceCheckType.yhpdmPing,
    ),
  ];

  @override
  void initState() {
    super.initState();
    // 启动时自动检测所有服务
    _checkAllServices();
  }

  /// 检测所有服务
  Future<void> _checkAllServices() async {
    // 并发执行所有检测，每个检测独立
    await Future.wait(_services.map((service) => _checkSingleService(service)));
  }

  /// 检测单个服务
  Future<void> _checkSingleService(_ServiceStatus service) async {
    // 设置为检测中
    setState(() {
      service.checking = true;
      service.ok = false;
    });

    try {
      final result = await _ping(service);
      
      if (!mounted) return;
      
      setState(() {
        service.checking = false;
        service.ok = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        service.checking = false;
        service.ok = false;
      });
    }
  }

  /// 实际检测逻辑 - 根据不同服务类型验证响应内容
  Future<bool> _ping(_ServiceStatus service) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    
    try {
      final req = await client.getUrl(Uri.parse(service.url));
      req.headers.set('User-Agent', getRandomUA());
      final res = await req.close();
      
      // 先检查HTTP状态码
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return false;
      }
      
      // 读取响应体
      String body = '';
      try {
        body = await res.transform(utf8.decoder).join();
      } catch (_) {
        return false;
      }
      
      // 根据服务类型验证响应内容
      switch (service.checkType) {
        case ServiceCheckType.bangumiCollection:
          return _validateBangumiCollection(body);
          
        case ServiceCheckType.bangumiComment:
          return _validateBangumiComment(body);
          
        case ServiceCheckType.yhpdmPing:
          return _validateYhpdmPing(body);
          
        default:
          return body.isNotEmpty;
      }
      
    } catch (e) {
      print('检测失败: ${service.url}, 错误: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// 验证收藏数据服务响应
  bool _validateBangumiCollection(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      // 必须有 data 字段且是列表
      if (json['data'] is! List) return false;
      
      final data = json['data'] as List;
      if (data.isEmpty) return false;
      
      // 检查第一个条目是否有必要字段
      final firstItem = data[0] as Map<String, dynamic>;
      return firstItem.containsKey('id') && 
             firstItem.containsKey('name') &&
             firstItem.containsKey('rating');
             
    } catch (_) {
      return false;
    }
  }

  /// 验证评论服务响应（/ping?pl）
  bool _validateBangumiComment(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      // 必须有 service 字段
      if (json['service'] != 'proxy_check') return false;
      
      // 必须有 proxy_check 字段
      if (json['proxy_check'] is! Map) return false;
      
      final proxyCheck = json['proxy_check'] as Map<String, dynamic>;
      
      // ok 必须为 true
      if (proxyCheck['ok'] != true) return false;
      
      // http_code 必须为 200
      if (proxyCheck['http_code'] != 200) return false;
      
      // 必须有 response 字段且不为空
      final response = proxyCheck['response'] as String?;
      if (response == null || response.isEmpty) return false;
      
      // 尝试解析 response 内的 JSON
      try {
        final innerJson = jsonDecode(response) as Map<String, dynamic>;
        // 至少要有 id 字段
        return innerJson.containsKey('id');
      } catch (_) {
        return false;
      }
      
    } catch (_) {
      return false;
    }
  }

  /// 验证樱花动漫 ping 服务
  bool _validateYhpdmPing(String body) {
    try {
      // 简单ping应该返回特定格式，或者至少不是空响应
      if (body.isEmpty) return false;
      
      // 尝试解析JSON
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      // 如果有 status 字段，检查是否为 ok
      if (json.containsKey('status')) {
        return json['status'] == 'ok' || json['status'] == 'success';
      }
      
      // 如果有 code 字段，检查是否为 0 或 200
      if (json.containsKey('code')) {
        final code = json['code'];
        return code == 0 || code == 200 || code == '0' || code == '200';
      }
      
      // 如果有 result 字段，检查是否为 ok
      if (json.containsKey('result')) {
        return json['result'] == 'ok' || json['result'] == 'success';
      }
      
      // 如果包含 data 字段且不为空
      if (json.containsKey('data') && json['data'] != null) {
        return true;
      }
      
      // 默认：只要不是错误响应就行
      return !body.contains('error') && !body.contains('failed');
      
    } catch (_) {
      // 如果不是JSON格式，检查是否包含特定关键词
      return body.contains('ok') || 
             body.contains('success') || 
             body.contains('pong');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allChecked = _services.every((s) => !s.checking);
    final allOk = allChecked && _services.every((s) => s.ok);

    return Scaffold(
      appBar: SysAppBar(title: const Text('代理')),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // 顶部状态文字（检测中 / 正常 / 异常）
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: Text(
                !allChecked
                    ? '正在检测连接，请稍后'
                    : (allOk ? '所有服务连接正常' : '部分服务连接异常'),
                key: ValueKey(allChecked ? (allOk ? 'ok' : 'fail') : 'checking'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: !allChecked
                      ? colorScheme.onSurfaceVariant
                      : (allOk
                          ? Colors.green.shade700
                          : Colors.orange.shade800),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 服务列表
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _services.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 56,
                          color: colorScheme.outlineVariant,
                        ),
                      _buildServiceTile(_services[i]),
                    ],
                  ],
                ),
              ),
            ),
            const Spacer(),
            // 底部操作栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Text(
                    '未启用代理',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  // 重新检测按钮
                  TextButton(
                    onPressed: _services.any((s) => s.checking) 
                        ? null 
                        : _checkAllServices,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade600,
                    ),
                    child: const Text('重新检测'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      context.pushNamed('/settings/proxy');
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade600,
                    ),
                    child: const Text('编辑'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceTile(_ServiceStatus service) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: service.avatar != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                service.avatar!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultLeading(service),
              ),
            )
          : _defaultLeading(service),
      title: Text(
        service.name,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        service.desc,
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: service.checking
            ? const SizedBox(
                key: ValueKey('loading'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : (service.ok
                ? const Icon(
                    Icons.check_circle_rounded,
                    key: ValueKey('ok'),
                    color: Colors.green,
                    size: 24,
                  )
                : const Icon(
                    Icons.cancel_rounded,
                    key: ValueKey('fail'),
                    color: Colors.redAccent,
                    size: 24,
                  )),
      ),
      // 点击单个服务重新检测
      onTap: service.checking ? null : () => _checkSingleService(service),
    );
  }

  Widget _defaultLeading(_ServiceStatus service) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        service.name == 'Bangumi' ? Icons.tv_rounded : Icons.cloud_rounded,
        size: 20,
        color: colorScheme.onPrimaryContainer,
      ),
    );
  }
}

/// 服务检测类型
enum ServiceCheckType {
  bangumiCollection,  // Bangumi 收藏数据
  bangumiComment,     // Bangumi 评论
  yhpdmPing,         // 樱花动漫 ping
}

class _ServiceStatus {
  _ServiceStatus({
    required this.name,
    required this.desc,
    required this.url,
    this.avatar,
    required this.checkType,
  });

  final String name;
  final String desc;
  final String url;
  final String? avatar;
  final ServiceCheckType checkType;
  
  bool ok = false;
  bool checking = false;  // 独立检测状态
}
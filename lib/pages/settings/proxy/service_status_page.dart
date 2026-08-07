import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/utils/http_headers.dart';

/// 代理/服务状态检测页
///
/// 检测 3 个服务连接状态：
/// - Bangumi 收藏数据服务
/// - Bangumi 评论服务
/// - 樱花动漫 弹幕/评论服务（qlyyz.xyz/ping）
class ServiceStatusPage extends StatefulWidget {
  const ServiceStatusPage({super.key});

  @override
  State<ServiceStatusPage> createState() => _ServiceStatusPageState();
}

class _ServiceStatusPageState extends State<ServiceStatusPage>
    with SingleTickerProviderStateMixin {
  bool _checking = true;
  final List<_ServiceStatus> _services = [
    _ServiceStatus(
      name: 'Bangumi',
      desc: '收藏数据服务',
      url: 'https://api.qlyyz.top',
      avatar: null,
    ),
    _ServiceStatus(
      name: 'Bangumi',
      desc: '评论服务',
      url: 'https://qlyyz.xyz/api/proxy',
      avatar: null,
    ),
    _ServiceStatus(
      name: '樱花动漫',
      desc: '弹幕,评论服务',
      url: 'https://qlyyz.xyz/ping',
      avatar: 'https://qlyyz.xyz/logo.webp',
    ),
  ];

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _runChecks();
  }

  Future<void> _runChecks() async {
    setState(() {
      _checking = true;
      for (final s in _services) {
        s.ok = false;
      }
    });
    // 并发检测
    await Future.wait(_services.map((s) async {
      s.ok = await _ping(s);
    }));
    if (!mounted) return;
    _animController.forward(from: 0);
    setState(() {
      _checking = false;
    });
  }

  Future<bool> _ping(_ServiceStatus service) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(service.url));
      req.headers.set('User-Agent', getRandomUA());
      final res = await req.close();
      final status = res.statusCode;
      // 尽量读取响应体（评论代理会返回"无效的 AppId"= 正常）
      String body = '';
      try {
        body = await res.transform(utf8.decoder).join();
      } catch (_) {}
      client.close();
      // 评论代理（/api/proxy）：404 = 异常（文件没部署）；其他响应（含"无效的 AppId"）= 正常
      if (service.url.contains('/api/proxy')) {
        if (status == 404) return false;
        return true;
      }
      // 收藏镜像（api.qlyyz.top）：根路径 404 是正常的（没加具体路径）；有响应即通
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allOk = !_checking && _services.every((s) => s.ok);

    return Scaffold(
      appBar: SysAppBar(title: const Text('代理')),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // 顶部状态文字（检测中 / 正常 / 异常），带切换动画
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: Text(
                _checking
                    ? '正在检测连接，请稍后'
                    : (allOk ? '所有服务连接正常' : '部分服务连接异常'),
                key: ValueKey(_checking ? 'checking' : (allOk ? 'ok' : 'fail')),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: _checking
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
            // 左下角：未启用代理；右下角：编辑
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
        child: _checking
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

class _ServiceStatus {
  _ServiceStatus({
    required this.name,
    required this.desc,
    required this.url,
    this.avatar,
  });

  final String name;
  final String desc;
  final String url;
  final String? avatar;
  bool ok = false;
}

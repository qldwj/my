import 'package:flutter/material.dart';
import 'package:yhdm/services/web_auth_service.dart';

/// 网页版授权登录 —— 应用端整页授权确认页
///
/// 模仿 QQ / 微信 OAuth 授权确认页：
///   - 整页全屏页面（不是弹窗）
///   - 白底卡片式布局
///   - 展示「谁在请求 + 将获得哪些权限」（网页端申请了才打 ✓，未申请显示 ✕）
///   - 点击「同意授权」后直接跳回网页端回调地址完成登录
///
/// 页面通过 Navigator.pop 返回：
///   - `WebAuthDecision.approve`：用户同意授权
///   - `WebAuthDecision.deny`：用户拒绝
enum WebAuthDecision { approve, deny }

class WebAuthPage extends StatefulWidget {
  const WebAuthPage({
    super.key,
    required this.request,
  });

  final WebAuthRequest request;

  static Future<WebAuthDecision?> push(
    BuildContext context, {
    required WebAuthRequest request,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<WebAuthDecision>(
        builder: (_) => WebAuthPage(request: request),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<WebAuthPage> createState() => _WebAuthPageState();
}

class _WebAuthPageState extends State<WebAuthPage> {
  late final String _appName;
  late final String _host;
  late final Set<String> _scopes;

  @override
  void initState() {
    super.initState();
    _appName = widget.request.appName.isNotEmpty ? widget.request.appName : '该网页';
    _host = Uri.tryParse(widget.request.redirect)?.host ?? widget.request.redirect;
    _scopes = widget.request.scopes.toSet();
  }

  bool _has(String scope) => _scopes.contains(scope);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 白底授权页：浅色固定用白卡片，深色主题下保持卡片风格
    final cardColor = isDark
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : Colors.white;
    final bgColor = isDark
        ? Theme.of(context).colorScheme.surface
        : const Color(0xFFF7F8FA);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 顶部：关闭 + 标题 ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 40),
                      Text(
                        '网页授权登录',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () =>
                            Navigator.pop(context, WebAuthDecision.deny),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 卡片主体 ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── 品牌区 ──
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFF9AC6), Color(0xFFF54EA2)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(
                              child: Text(
                                '🌸',
                                style: TextStyle(fontSize: 30),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '樱花动漫',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '网页授权登录',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '授权后即可使用樱花动漫账号登录本站',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),

                        // ── 站点地址 ──
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.language,
                                size: 16,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _host,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── 权限列表 ──
                        const SizedBox(height: 20),
                        Text(
                          '授权后将获得以下权限',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ScopeTile(
                          icon: Icons.alternate_email,
                          title: '邮箱',
                          granted: _has('email'),
                        ),
                        _ScopeTile(
                          icon: Icons.verified_user,
                          title: '保持登录状态',
                          granted: _has('keep'),
                        ),
                        _ScopeTile(
                          icon: Icons.star_outline_rounded,
                          title: '读写你的收藏',
                          granted: _has('collect'),
                        ),
                        _ScopeTile(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: '发表评论 / 私信',
                          granted: _has('comment'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '以上权限需本站主动申请后才可获得，具体以实际使用为准。',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),

                        // ── 授权按钮 ──
                        const SizedBox(height: 24),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF07C160),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () =>
                              Navigator.pop(context, WebAuthDecision.approve),
                          child: const Text('同意授权'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(context, WebAuthDecision.deny),
                          child: Text(
                            '拒绝',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '不会泄露你的密码，授权资料仅用于该网站登录。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一条权限说明（网页端申请了显示 ✓，未申请显示 ✕）
class _ScopeTile extends StatelessWidget {
  const _ScopeTile({
    required this.icon,
    required this.title,
    required this.granted,
  });

  final IconData icon;
  final String title;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Icon(
            granted ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: granted
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}
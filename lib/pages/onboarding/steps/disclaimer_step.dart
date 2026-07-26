import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:kazumi/pages/onboarding/onboarding_step_layout.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:url_launcher/url_launcher.dart';

class DisclaimerStep extends StatefulWidget {
  const DisclaimerStep({super.key, this.onScrolledToBottom});

  final VoidCallback? onScrolledToBottom;

  @override
  State<DisclaimerStep> createState() => _DisclaimerStepState();
}

class _DisclaimerStepState extends State<DisclaimerStep> {
  String? statementsText;
  final _scrollController = ScrollController();
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _loadStatements();
    _scrollController.addListener(() {
      if (_reported) return;
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 10) {
        _reported = true;
        widget.onScrolledToBottom?.call();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStatements() async {
    String text;
    try {
      text = await rootBundle.loadString('assets/statements/statements.txt');
    } catch (error, stackTrace) {
      KazumiLogger().e('Onboarding: failed to load statements', error: error, stackTrace: stackTrace);
      text = '免责声明加载失败，请退出后重试。';
    }
    if (!mounted) return;
    setState(() => statementsText = text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_reported && _scrollController.position.maxScrollExtent <= 0) {
        _reported = true;
        widget.onScrolledToBottom?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return OnboardingStepLayout(
      leading: const OnboardingStepIcon(icon: Icons.waving_hand_rounded),
      title: '欢迎使用',
      subtitle: '请滑到底部并同意免责声明',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.language, size: 18),
                label: const Text('官网'),
                onPressed: () => launchUrl(Uri.parse(ApiEndpoints.projectUrl), mode: LaunchMode.externalApplication),
              ),
              const SizedBox(width: 12),
              ActionChip(
                avatar: const Icon(Icons.telegram, size: 18),
                label: const Text('Telegram'),
                onPressed: () => launchUrl(Uri.parse(ApiEndpoints.telegramGroup), mode: LaunchMode.externalApplication),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: statementsText == null
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(20),
                      child: Text(statementsText!, style: textTheme.bodyMedium?.copyWith(height: 1.7)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

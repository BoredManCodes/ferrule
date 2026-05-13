import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/crash_consent.dart';

class CrashConsentScreen extends ConsumerStatefulWidget {
  const CrashConsentScreen({super.key});

  @override
  ConsumerState<CrashConsentScreen> createState() => _CrashConsentScreenState();
}

class _CrashConsentScreenState extends ConsumerState<CrashConsentScreen> {
  bool _busy = false;

  Future<void> _choose(bool optIn) async {
    if (_busy) return;
    setState(() => _busy = true);
    final notifier = ref.read(crashConsentProvider.notifier);
    if (optIn) {
      await notifier.optIn();
    } else {
      await notifier.optOut();
    }
    // Router refresh-listener will redirect to /setup once consent is set.
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.bug_report_outlined,
                            size: 36,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Help improve this app',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'When the app crashes or hits an unexpected error, you can '
                        'help by sending an anonymous report so the bug can be fixed.',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                      ),
                      const SizedBox(height: 24),
                      _Bullets(
                        title: 'What gets sent',
                        items: const [
                          'A stack trace of the error',
                          'App version, OS version, and device model',
                          'A small sample of performance traces (≈10%)',
                        ],
                        icon: Icons.check_circle_outline,
                        color: scheme.primary,
                        scheme: scheme,
                      ),
                      const SizedBox(height: 16),
                      _Bullets(
                        title: 'What never gets sent',
                        items: const [
                          'Your ITFlow URL, API key, or vault password',
                          'Your agent login email or password',
                          'Ticket content, asset data, or anything from your instance',
                          'Personal identifiers (no PII, no device IDs)',
                        ],
                        icon: Icons.shield_outlined,
                        color: scheme.tertiary,
                        scheme: scheme,
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 18, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Crash reports are processed by Sentry. You can '
                                'change this anytime in Settings.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _choose(true),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.favorite_outline),
                        label: const Text('Send crash reports'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : () => _choose(false),
                        child: const Text('No thanks'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bullets extends StatelessWidget {
  final String title;
  final List<String> items;
  final IconData icon;
  final Color color;
  final ColorScheme scheme;

  const _Bullets({
    required this.title,
    required this.items,
    required this.icon,
    required this.color,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        ...items.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: scheme.onSurface,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

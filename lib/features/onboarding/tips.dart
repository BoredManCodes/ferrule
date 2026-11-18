import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/ui_prefs.dart';

/// A one-time hint shown the first time a screen is opened, until the user
/// taps Got it. Settings > Help can bring them all back.
class FirstVisitTip extends ConsumerWidget {
  final String id;
  final String text;
  final IconData icon;
  final EdgeInsetsGeometry margin;
  const FirstVisitTip({
    super.key,
    required this.id,
    required this.text,
    this.icon = Icons.lightbulb_outline,
    this.margin = const EdgeInsets.fromLTRB(12, 8, 12, 8),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(uiPrefsProvider);
    // Nothing until prefs load, so a seen tip never flashes up.
    final seen = prefs.value?.tipsSeen.contains(id) ?? true;
    if (seen) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: scheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(text,
                      style: TextStyle(
                          color: scheme.onSecondaryContainer, height: 1.3)),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () =>
                  ref.read(uiPrefsProvider.notifier).markTipSeen(id),
              child: const Text('Got it'),
            ),
          ),
        ],
      ),
    );
  }
}

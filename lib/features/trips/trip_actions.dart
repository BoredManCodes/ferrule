import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import 'active_trip.dart';

/// Shared entry point for "start a new trip" — used by the Trips landing
/// screen *and* the home-screen quick-start button. Honours the user's saved
/// trip-mode preference (GPS / manual), and prompts on first use if it's
/// unset. Returns silently if the user cancels.
Future<void> startTripFlow(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(appSettingsProvider).value;
  var mode = settings?.tripMode;
  if (mode == null) {
    final picked = await _askMode(context);
    if (picked == null) return;
    await ref.read(appSettingsProvider.notifier).setTripMode(picked);
    mode = picked;
  }
  if (!context.mounted) return;
  if (mode == 'manual') {
    await ref.read(activeTripProvider.notifier).startWith(
          ActiveTrip(isGps: false, startedAt: DateTime.now()),
        );
    if (!context.mounted) return;
    context.push('/trips/active');
  } else {
    context.push('/trips/start');
  }
}

Future<String?> _askMode(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('How do you want to track trips?'),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: Text(
            'You can change this later in Settings → Trips.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        _ModeOption(
          icon: Icons.my_location,
          title: 'GPS tracking',
          subtitle: 'Record start/end location automatically and calculate '
              'miles from your route.',
          value: 'gps',
        ),
        _ModeOption(
          icon: Icons.timer_outlined,
          title: 'Manual start / stop',
          subtitle: 'Just time the trip — enter the miles yourself at the end.',
          value: 'manual',
        ),
      ],
    ),
  );
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  const _ModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

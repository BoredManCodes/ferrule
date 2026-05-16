import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/providers.dart';
import 'active_trip.dart';
import 'trip_actions.dart';

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasWebCreds = ref.watch(itflowWebClientProvider) != null;
    final active = ref.watch(activeTripProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!hasWebCreds) ...[
            const _NeedsAgentCredsBanner(),
            const SizedBox(height: 16),
          ],
          active.when(
            loading: () => const _LoadingCard(),
            error: (e, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$e'),
              ),
            ),
            data: (t) => t == null
                ? _StartCard(disabled: !hasWebCreds)
                : _InProgressCard(trip: t),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
}

class _StartCard extends ConsumerWidget {
  final bool disabled;
  const _StartCard({required this.disabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.route_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Log a trip',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Start a trip to time it on this device. With GPS, miles and '
              'addresses are filled in automatically when you stop; without '
              'GPS you enter them yourself.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  disabled ? null : () => startTripFlow(context, ref),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start trip'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: disabled ? null : () => context.push('/trips/new'),
              icon: const Icon(Icons.edit_note),
              label: const Text('Log past trip'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InProgressCard extends ConsumerWidget {
  final ActiveTrip trip;
  const _InProgressCard({required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(tripTickProvider);
    final scheme = Theme.of(context).colorScheme;
    final elapsed = trip.elapsed();
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.directions_car, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text('Trip in progress',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        )),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              trip.startAddress.isEmpty
                  ? 'Starting location captured'
                  : 'From: ${trip.startAddress}',
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 4),
            Text(
              'Started ${DateFormat.jm().format(trip.startedAt)} '
              '• ${_format(elapsed)}',
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/trips/active'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open trip'),
            ),
          ],
        ),
      ),
    );
  }

  String _format(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _NeedsAgentCredsBanner extends StatelessWidget {
  const _NeedsAgentCredsBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agent sign-in required',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ITFlow\'s API doesn\'t expose trip endpoints, so trips '
                    'are submitted by signing in as you in the background. '
                    'Add your agent email + password in Settings to enable trips.',
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

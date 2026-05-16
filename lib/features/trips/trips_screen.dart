import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/providers.dart';
import 'active_trip.dart';
import 'trip.dart';
import 'trip_actions.dart';
import 'trip_repository.dart';

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasWebCreds = ref.watch(itflowWebClientProvider) != null;
    final active = ref.watch(activeTripProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(tripListProvider);
          await ref.read(tripListProvider.future).catchError((_) => <Trip>[]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
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
            if (hasWebCreds) ...[
              const SizedBox(height: 24),
              const _PastTripsSection(),
            ],
          ],
        ),
      ),
    );
  }
}

class _PastTripsSection extends ConsumerWidget {
  const _PastTripsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tripListProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Past trips',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        async.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Couldn\'t load past trips',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: scheme.onErrorContainer,
                          )),
                  const SizedBox(height: 4),
                  Text('$e',
                      style: TextStyle(color: scheme.onErrorContainer)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => ref.invalidate(tripListProvider),
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          data: (trips) {
            if (trips.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No trips yet. Start one above or log one manually.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < trips.length; i++) ...[
                    _TripRow(trip: trips[i]),
                    if (i < trips.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TripRow extends StatelessWidget {
  final Trip trip;
  const _TripRow({required this.trip});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = StringBuffer()
      ..write(trip.source.isEmpty ? '—' : trip.source)
      ..write(' → ')
      ..write(trip.destination.isEmpty ? '—' : trip.destination);
    final meta = <String>[
      _formatDate(trip.date),
      if (trip.driver.isNotEmpty) trip.driver,
      if (trip.clientName != null && trip.clientName!.isNotEmpty)
        trip.clientName!,
    ].join(' • ');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(trip.roundtrip
            ? Icons.sync_alt
            : Icons.arrow_right_alt),
      ),
      title: Text(
        trip.purpose.isEmpty ? 'Trip' : trip.purpose,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle.toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                meta,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
      trailing: Text(
        '${trip.miles.toStringAsFixed(1)} mi',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      isThreeLine: true,
    );
  }

  String _formatDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat.yMMMd().format(parsed);
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

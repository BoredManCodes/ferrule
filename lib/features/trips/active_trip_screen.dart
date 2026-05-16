import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'active_trip.dart';
import 'trip_form_data.dart';
import 'trip_repository.dart';

class ActiveTripScreen extends ConsumerStatefulWidget {
  const ActiveTripScreen({super.key});

  @override
  ConsumerState<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends ConsumerState<ActiveTripScreen> {
  bool _stopping = false;
  String _stopStatus = '';
  Object? _stopError;

  Future<void> _stop(ActiveTrip trip) async {
    if (!trip.isGps) {
      // Manual mode: no GPS to capture — straight to the review form. The user
      // fills in source / destination / miles by hand. We clear the active
      // trip first so the user can't "stop" twice.
      await ref.read(activeTripProvider.notifier).stopAndClear();
      if (!mounted) return;
      context.pushReplacement('/trips/new');
      return;
    }

    setState(() {
      _stopping = true;
      _stopStatus = 'Capturing end location…';
      _stopError = null;
    });
    try {
      final svc = ref.read(locationServiceProvider);
      final fix = await svc.currentFix();
      if (!mounted) return;
      setState(() => _stopStatus = 'Resolving address…');
      final endAddr = await svc.reverseGeocode(fix.lat, fix.lng);
      if (!mounted) return;
      setState(() => _stopStatus = 'Calculating distance…');
      final km = await svc.drivingDistanceKm(
        startLat: trip.startLat!,
        startLng: trip.startLng!,
        endLat: fix.lat,
        endLng: fix.lng,
      );
      final miles = km * 0.621371;
      if (!mounted) return;

      final draft = TripDraft(
        date: DateTime.now(),
        miles: miles,
        source: trip.startAddress,
        destination: endAddr,
      );

      await ref.read(activeTripProvider.notifier).stopAndClear();
      if (!mounted) return;
      context.pushReplacement('/trips/new', extra: draft);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stopError = e;
        _stopping = false;
      });
    }
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard trip?'),
        content: const Text(
            'This will throw away the starting point. The trip won\'t be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(activeTripProvider.notifier).discard();
    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeTripProvider);
    ref.watch(tripTickProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip in progress'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Discard trip',
            onPressed: _stopping ? null : _discard,
          ),
        ],
      ),
      body: active.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (trip) {
          if (trip == null) {
            // Trip was cleared elsewhere — bounce back to /trips.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/trips');
            });
            return const SizedBox.shrink();
          }
          return _Body(
            trip: trip,
            stopping: _stopping,
            stopStatus: _stopStatus,
            stopError: _stopError,
            onStop: () => _stop(trip),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final ActiveTrip trip;
  final bool stopping;
  final String stopStatus;
  final Object? stopError;
  final VoidCallback onStop;
  const _Body({
    required this.trip,
    required this.stopping,
    required this.stopStatus,
    required this.stopError,
    required this.onStop,
  });

  String _format(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final elapsed = trip.elapsed();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Elapsed',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _format(elapsed),
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontFeatures: const [],
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Started ${DateFormat.jm().format(trip.startedAt)}',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          trip.isGps
                              ? Icons.my_location
                              : Icons.timer_outlined,
                          color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                          trip.isGps
                              ? 'Starting location'
                              : 'Manual trip',
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    trip.isGps
                        ? (trip.startAddress.isEmpty
                            ? '${trip.startLat?.toStringAsFixed(5) ?? "?"}, '
                                '${trip.startLng?.toStringAsFixed(5) ?? "?"}'
                            : trip.startAddress)
                        : 'You\'ll enter the source, destination, and miles '
                            'when you stop.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (stopError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                stopError.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: stopping ? null : onStop,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            icon: stopping
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.stop_circle_outlined),
            label: Text(stopping
                ? (stopStatus.isEmpty ? 'Stopping…' : stopStatus)
                : 'Stop trip'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/location_service.dart';
import 'active_trip.dart';
import 'trip_repository.dart';

class StartTripScreen extends ConsumerStatefulWidget {
  const StartTripScreen({super.key});

  @override
  ConsumerState<StartTripScreen> createState() => _StartTripScreenState();
}

class _StartTripScreenState extends ConsumerState<StartTripScreen> {
  String _status = 'Locating you…';
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    setState(() {
      _status = 'Locating you…';
      _error = null;
    });
    try {
      final fix = await ref.read(locationServiceProvider).currentFix();
      if (!mounted) return;
      setState(() => _status = 'Resolving address…');
      final addr = await ref
          .read(locationServiceProvider)
          .reverseGeocode(fix.lat, fix.lng);
      if (!mounted) return;
      final trip = ActiveTrip(
        isGps: true,
        startedAt: DateTime.now(),
        startLat: fix.lat,
        startLng: fix.lng,
        startAddress: addr,
      );
      await ref.read(activeTripProvider.notifier).startWith(trip);
      if (!mounted) return;
      context.pushReplacement('/trips/active');
    } on LocationUnavailable catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Start Trip')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(_status,
                        style: Theme.of(context).textTheme.bodyLarge),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_disabled,
                        size: 48, color: scheme.error),
                    const SizedBox(height: 16),
                    Text(
                      _error.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: () => context.pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonal(
                          onPressed: _begin,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

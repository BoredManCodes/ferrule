import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/services/trip_notifications.dart';

/// The starting snapshot for an in-progress trip. Persisted to secure storage
/// so it survives app close — the trip is only finalised when the user taps
/// "Stop" and submits the review form.
class ActiveTrip {
  /// `true` when this trip was started via GPS and start coordinates were
  /// captured; `false` for a manual trip where the user enters miles by hand.
  final bool isGps;
  final DateTime startedAt;
  final double? startLat;
  final double? startLng;
  final String startAddress;

  const ActiveTrip({
    required this.isGps,
    required this.startedAt,
    this.startLat,
    this.startLng,
    this.startAddress = '',
  });

  Duration elapsed([DateTime? now]) =>
      (now ?? DateTime.now()).difference(startedAt);

  Map<String, dynamic> toJson() => {
        'isGps': isGps,
        'startedAt': startedAt.toIso8601String(),
        'startLat': startLat,
        'startLng': startLng,
        'startAddress': startAddress,
      };

  factory ActiveTrip.fromJson(Map<String, dynamic> j) => ActiveTrip(
        // Default to GPS for backwards compat with earlier records that didn't
        // store the flag.
        isGps: j['isGps'] as bool? ?? true,
        startedAt: DateTime.parse(j['startedAt'] as String),
        startLat: (j['startLat'] as num?)?.toDouble(),
        startLng: (j['startLng'] as num?)?.toDouble(),
        startAddress: j['startAddress'] as String? ?? '',
      );
}

class ActiveTripController extends AsyncNotifier<ActiveTrip?> {
  static const _storageKey = 'active_trip';
  final _storage = const FlutterSecureStorage();

  @override
  Future<ActiveTrip?> build() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final trip =
          ActiveTrip.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      // Restore the persistent notification if the app was killed mid-trip.
      await ref.read(tripNotificationsProvider).showActiveTrip(
            isGps: trip.isGps,
            startedAt: trip.startedAt,
            startAddress: trip.startAddress,
          );
      return trip;
    } catch (_) {
      await _storage.delete(key: _storageKey);
      return null;
    }
  }

  Future<void> _persist(ActiveTrip? t) async {
    if (t == null) {
      await _storage.delete(key: _storageKey);
    } else {
      await _storage.write(key: _storageKey, value: jsonEncode(t.toJson()));
    }
  }

  Future<void> startWith(ActiveTrip trip) async {
    await _persist(trip);
    await ref.read(tripNotificationsProvider).showActiveTrip(
          isGps: trip.isGps,
          startedAt: trip.startedAt,
          startAddress: trip.startAddress,
        );
    state = AsyncValue.data(trip);
  }

  Future<ActiveTrip?> stopAndClear() async {
    final cur = state.value;
    await _persist(null);
    await ref.read(tripNotificationsProvider).clear();
    state = const AsyncValue.data(null);
    return cur;
  }

  Future<void> discard() async {
    await _persist(null);
    await ref.read(tripNotificationsProvider).clear();
    state = const AsyncValue.data(null);
  }
}

final activeTripProvider =
    AsyncNotifierProvider<ActiveTripController, ActiveTrip?>(
        ActiveTripController.new);

/// Emits once a second while a trip is active so the elapsed-time widgets can
/// rebuild. No emissions when nothing is active.
final tripTickProvider = StreamProvider.autoDispose<int>((ref) {
  final active = ref.watch(activeTripProvider).value;
  if (active == null) return const Stream<int>.empty();
  return Stream<int>.periodic(const Duration(seconds: 1), (i) => i + 1);
});

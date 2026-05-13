import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ActiveTimer {
  final int ticketId;
  final String? ticketLabel;
  final DateTime startedAt;
  final Duration accumulated;
  final bool running;

  ActiveTimer({
    required this.ticketId,
    this.ticketLabel,
    required this.startedAt,
    this.accumulated = Duration.zero,
    this.running = true,
  });

  Duration elapsed([DateTime? now]) {
    final n = now ?? DateTime.now();
    if (!running) return accumulated;
    return accumulated + n.difference(startedAt);
  }

  ActiveTimer pause() => ActiveTimer(
        ticketId: ticketId,
        ticketLabel: ticketLabel,
        startedAt: startedAt,
        accumulated: elapsed(),
        running: false,
      );

  ActiveTimer resume() => ActiveTimer(
        ticketId: ticketId,
        ticketLabel: ticketLabel,
        startedAt: DateTime.now(),
        accumulated: accumulated,
        running: true,
      );

  Map<String, dynamic> toJson() => {
        'ticketId': ticketId,
        'ticketLabel': ticketLabel,
        'startedAt': startedAt.toIso8601String(),
        'accumulatedMs': accumulated.inMilliseconds,
        'running': running,
      };

  factory ActiveTimer.fromJson(Map<String, dynamic> j) => ActiveTimer(
        ticketId: j['ticketId'] as int,
        ticketLabel: j['ticketLabel'] as String?,
        startedAt: DateTime.parse(j['startedAt'] as String),
        accumulated:
            Duration(milliseconds: (j['accumulatedMs'] as num).toInt()),
        running: j['running'] as bool? ?? true,
      );
}

class TimerController extends AsyncNotifier<ActiveTimer?> {
  static const _storageKey = 'active_timer';
  final _storage = const FlutterSecureStorage();

  @override
  Future<ActiveTimer?> build() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return ActiveTimer.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _storage.delete(key: _storageKey);
      return null;
    }
  }

  Future<void> _persist(ActiveTimer? t) async {
    if (t == null) {
      await _storage.delete(key: _storageKey);
    } else {
      await _storage.write(key: _storageKey, value: jsonEncode(t.toJson()));
    }
  }

  Future<void> start(int ticketId, {String? label}) async {
    final t = ActiveTimer(
      ticketId: ticketId,
      ticketLabel: label,
      startedAt: DateTime.now(),
    );
    await _persist(t);
    state = AsyncValue.data(t);
  }

  Future<void> pause() async {
    final cur = state.value;
    if (cur == null || !cur.running) return;
    final paused = cur.pause();
    await _persist(paused);
    state = AsyncValue.data(paused);
  }

  Future<void> resume() async {
    final cur = state.value;
    if (cur == null || cur.running) return;
    final resumed = cur.resume();
    await _persist(resumed);
    state = AsyncValue.data(resumed);
  }

  Future<Duration> stop() async {
    final cur = state.value;
    if (cur == null) return Duration.zero;
    final total = cur.elapsed();
    await _persist(null);
    state = const AsyncValue.data(null);
    return total;
  }

  Future<void> discard() async {
    await _persist(null);
    state = const AsyncValue.data(null);
  }
}

final activeTimerProvider =
    AsyncNotifierProvider<TimerController, ActiveTimer?>(
        TimerController.new);

/// Emits once a second while there's a running timer being observed.
/// Widgets that render the elapsed time should `ref.watch(timerTickProvider)`
/// so they rebuild every second. Paused/absent timers don't tick.
final timerTickProvider = StreamProvider.autoDispose<int>((ref) {
  final active = ref.watch(activeTimerProvider).value;
  if (active == null || !active.running) {
    return const Stream<int>.empty();
  }
  return Stream<int>.periodic(const Duration(seconds: 1), (i) => i + 1);
});

String formatDuration(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

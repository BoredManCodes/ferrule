import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TimeLogEntry {
  final int ticketId;
  final String? ticketLabel;
  final DateTime loggedAt;
  final Duration duration;
  final bool submitted;
  final String? note;

  TimeLogEntry({
    required this.ticketId,
    this.ticketLabel,
    required this.loggedAt,
    required this.duration,
    this.submitted = false,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'ticketId': ticketId,
        'ticketLabel': ticketLabel,
        'loggedAt': loggedAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'submitted': submitted,
        'note': note,
      };

  factory TimeLogEntry.fromJson(Map<String, dynamic> j) => TimeLogEntry(
        ticketId: j['ticketId'] as int,
        ticketLabel: j['ticketLabel'] as String?,
        loggedAt: DateTime.parse(j['loggedAt'] as String),
        duration:
            Duration(milliseconds: (j['durationMs'] as num).toInt()),
        submitted: j['submitted'] as bool? ?? false,
        note: j['note'] as String?,
      );
}

class TimeLogHistory extends AsyncNotifier<List<TimeLogEntry>> {
  static const _key = 'time_log_history';
  final _storage = const FlutterSecureStorage();

  @override
  Future<List<TimeLogEntry>> build() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              TimeLogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(TimeLogEntry e) async {
    final list = <TimeLogEntry>[e, ...(state.value ?? const <TimeLogEntry>[])];
    // Cap at 100 entries
    if (list.length > 100) list.removeRange(100, list.length);
    await _storage.write(
        key: _key,
        value: jsonEncode(list.map((x) => x.toJson()).toList()));
    state = AsyncValue.data(list);
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
    state = const AsyncValue.data([]);
  }
}

final timeLogHistoryProvider =
    AsyncNotifierProvider<TimeLogHistory, List<TimeLogEntry>>(
        TimeLogHistory.new);

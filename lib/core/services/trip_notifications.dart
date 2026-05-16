import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Persistent system notification that tells the user "a trip is currently
/// being tracked". Posted whenever an [ActiveTrip] exists, cleared on stop or
/// discard. The notification is ongoing (sticky on Android) so it can't be
/// swiped away accidentally — that's the only signal the app gives once
/// minimized, since the app doesn't run a background service.
class TripNotifications {
  static const int _activeTripId = 100;
  static const String _channelId = 'trip_active';
  static const String _channelName = 'Trip in progress';
  static const String _channelDescription =
      'Shown while a Ferrule trip is being tracked.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        await android.requestNotificationsPermission();
      } catch (_) {/* user denied or pre-Android 13 */}
      await android.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ));
    }

    _initialized = true;
  }

  Future<void> showActiveTrip({
    required bool isGps,
    required DateTime startedAt,
    String startAddress = '',
  }) async {
    try {
      await _ensureInitialized();
      final started = DateFormat.jm().format(startedAt);
      final body = isGps
          ? (startAddress.isEmpty
              ? 'GPS trip started at $started.'
              : 'From $startAddress • started $started')
          : 'Manual trip started at $started.';
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: false,
        playSound: false,
        enableVibration: false,
        category: AndroidNotificationCategory.status,
      );
      const darwinDetails = DarwinNotificationDetails(
        presentSound: false,
        presentBadge: false,
        interruptionLevel: InterruptionLevel.passive,
      );
      await _plugin.show(
        _activeTripId,
        'Trip in progress',
        body,
        const NotificationDetails(android: androidDetails, iOS: darwinDetails),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TripNotifications.showActiveTrip failed: $e');
      }
    }
  }

  Future<void> clear() async {
    try {
      await _ensureInitialized();
      await _plugin.cancel(_activeTripId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TripNotifications.clear failed: $e');
      }
    }
  }
}

final tripNotificationsProvider =
    Provider<TripNotifications>((ref) => TripNotifications());

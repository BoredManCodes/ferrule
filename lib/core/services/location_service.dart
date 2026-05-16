import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

/// Google Maps Platform key used for the Distance Matrix and reverse-geocoding
/// REST calls. Same key as the Jim2 TPW app — override at build time with
/// `--dart-define=GOOGLE_MAPS_API_KEY=...` if a different key is desired.
const String googleMapsApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: 'AIzaSyDCzI-zTH4NUmddtAIP5yAdNOsq9GbYcL0',
);

class LocationUnavailable implements Exception {
  final String message;
  LocationUnavailable(this.message);
  @override
  String toString() => message;
}

class LocationFix {
  final double lat;
  final double lng;
  final double? accuracyMeters;
  final DateTime capturedAt;
  const LocationFix({
    required this.lat,
    required this.lng,
    required this.capturedAt,
    this.accuracyMeters,
  });
}

class LocationService {
  final Dio _dio;
  LocationService({Dio? dio}) : _dio = dio ?? Dio();

  /// Requests permissions if needed and returns a single high-accuracy fix.
  /// Throws [LocationUnavailable] if services are off or permission denied.
  Future<LocationFix> currentFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationUnavailable(
          'Location services are turned off on this device.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw LocationUnavailable(
          'Location permission denied. Enable it to track trips.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw LocationUnavailable(
          'Location permission was denied permanently. Enable it in system settings.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return LocationFix(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyMeters: pos.accuracy,
      capturedAt: pos.timestamp,
    );
  }

  /// Best-effort reverse geocoding. Tries the on-device geocoder first (free),
  /// then falls back to Google's reverse-geocoding REST API. Returns a
  /// human-readable address, or just `"lat, lng"` if both fail.
  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await geo.placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 8));
      if (placemarks.isNotEmpty) {
        final s = _formatPlacemark(placemarks.first);
        if (s.isNotEmpty) return s;
      }
    } catch (_) {/* fall through to Google */}

    try {
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '$lat,$lng',
          'key': googleMapsApiKey,
        },
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final data = resp.data;
      if (data is Map && data['status'] == 'OK') {
        final results = data['results'];
        if (results is List && results.isNotEmpty) {
          final first = results.first;
          if (first is Map && first['formatted_address'] is String) {
            return first['formatted_address'] as String;
          }
        }
      }
    } catch (_) {/* keep falling */}

    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  String _formatPlacemark(geo.Placemark p) {
    final parts = <String>[
      if ((p.street ?? '').trim().isNotEmpty) p.street!.trim(),
      if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
      if ((p.administrativeArea ?? '').trim().isNotEmpty)
        p.administrativeArea!.trim(),
      if ((p.postalCode ?? '').trim().isNotEmpty) p.postalCode!.trim(),
    ];
    return parts.join(', ');
  }

  /// Driving distance in km between two points. Calls Google Distance Matrix
  /// first; falls back to a straight-line Haversine if the API is unavailable
  /// or returns a non-OK status. Always returns a non-negative value.
  Future<double> drivingDistanceKm({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    try {
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/distancematrix/json',
        queryParameters: {
          'origins': '$startLat,$startLng',
          'destinations': '$endLat,$endLng',
          'units': 'metric',
          'key': googleMapsApiKey,
        },
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final data = resp.data;
      if (data is Map && data['status'] == 'OK') {
        final rows = data['rows'];
        if (rows is List && rows.isNotEmpty) {
          final elements = rows.first is Map ? rows.first['elements'] : null;
          if (elements is List && elements.isNotEmpty) {
            final first = elements.first;
            if (first is Map && first['status'] == 'OK') {
              final meters = first['distance']?['value'];
              if (meters is num) return meters / 1000.0;
            }
          }
        }
      }
    } catch (_) {/* fall through to haversine */}

    final meters =
        Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
    return meters / 1000.0;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/services/location_service.dart';
import 'trip.dart';
import 'trip_form_data.dart';

class TripRepository {
  final Ref ref;
  TripRepository(this.ref);

  Future<TripAddFormData> fetchAddForm() async {
    final web = requireWebClient(ref);
    return web.fetchTripAddForm();
  }

  Future<List<Trip>> fetchList() async {
    final web = requireWebClient(ref);
    return web.fetchTripList();
  }

  Future<void> add({
    required String csrfToken,
    required String date,
    required double miles,
    required String source,
    required String destination,
    required String purpose,
    required int driverId,
    required int clientId,
    bool roundtrip = false,
  }) async {
    final web = requireWebClient(ref);
    await web.addTrip(
      csrfToken: csrfToken,
      date: date,
      miles: miles,
      source: source,
      destination: destination,
      purpose: purpose,
      driverId: driverId,
      clientId: clientId,
      roundtrip: roundtrip,
    );
  }
}

final tripRepositoryProvider =
    Provider<TripRepository>((ref) => TripRepository(ref));

final tripAddFormProvider =
    FutureProvider.autoDispose<TripAddFormData>((ref) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(tripRepositoryProvider).fetchAddForm();
});

final tripListProvider = FutureProvider.autoDispose<List<Trip>>((ref) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(tripRepositoryProvider).fetchList();
});

final locationServiceProvider =
    Provider<LocationService>((ref) => LocationService());

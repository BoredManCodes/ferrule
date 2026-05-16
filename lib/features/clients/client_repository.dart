import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/util.dart';
import 'client_model.dart';

class ClientRepository {
  final Ref ref;
  ClientRepository(this.ref);

  Future<List<Client>> list({
    int pageSize = 500,
    int maxItems = 50000,
    void Function(int loaded)? onProgress,
  }) async {
    final client = requireClient(ref);
    final all = <Client>[];
    var offset = 0;
    while (offset < maxItems) {
      final resp = await client.get('clients', 'read', query: {
        'limit': pageSize,
        'offset': offset,
      });
      if (!resp.success) break;
      final rows = resp.rows;
      if (rows.isEmpty) break;
      all.addAll(rows.map(Client.fromRow));
      onProgress?.call(all.length);
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  }

  Future<Client?> get(int id) async {
    final client = requireClient(ref);
    final resp = await client.get('clients', 'read', query: {'client_id': id});
    if (!resp.success || resp.row == null) return null;
    return Client.fromRow(resp.row!);
  }

  Future<bool> archive(int id) async {
    final client = requireClient(ref);
    final resp =
        await client.post('clients', 'archive', body: {'client_id': id});
    return resp.success;
  }

  Future<bool> unarchive(int id) async {
    final client = requireClient(ref);
    final resp =
        await client.post('clients', 'unarchive', body: {'client_id': id});
    return resp.success;
  }
}

final clientRepositoryProvider =
    Provider<ClientRepository>((ref) => ClientRepository(ref));

final clientsProvider =
    FutureProvider.autoDispose<List<Client>>((ref) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(clientRepositoryProvider).list();
});

final clientProvider =
    FutureProvider.autoDispose.family<Client?, int>((ref, id) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(clientRepositoryProvider).get(id);
});

/// All locations belonging to the given client. ITFlow's locations API doesn't
/// accept a client filter (only API-key-bound filtering), so we page through
/// every location and filter client-side. For typical instances the location
/// table is small.
final clientLocationsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, clientId) async {
  await ref.watch(credentialsProvider.future);
  final client = requireClient(ref);
  const pageSize = 500;
  const maxItems = 10000;
  final out = <Map<String, dynamic>>[];
  var offset = 0;
  while (offset < maxItems) {
    final resp = await client
        .get('locations', 'read', query: {'limit': pageSize, 'offset': offset});
    if (!resp.success) break;
    final rows = resp.rows;
    if (rows.isEmpty) break;
    for (final r in rows) {
      if (toInt(r['location_client_id']) == clientId) out.add(r);
    }
    if (rows.length < pageSize) break;
    offset += pageSize;
  }
  return out;
});

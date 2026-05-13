import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
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

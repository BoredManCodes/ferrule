import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import 'contact_model.dart';

class ContactRepository {
  final Ref ref;
  ContactRepository(this.ref);

  Future<List<Contact>> list({
    int pageSize = 500,
    int maxItems = 50000,
    void Function(int loaded)? onProgress,
  }) async {
    final client = requireClient(ref);
    final all = <Contact>[];
    var offset = 0;
    while (offset < maxItems) {
      final resp = await client.get('contacts', 'read', query: {
        'limit': pageSize,
        'offset': offset,
      });
      if (!resp.success) break;
      final rows = resp.rows;
      if (rows.isEmpty) break;
      all.addAll(rows.map(Contact.fromRow));
      onProgress?.call(all.length);
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  }

  Future<Contact?> get(int id) async {
    final client = requireClient(ref);
    final resp =
        await client.get('contacts', 'read', query: {'contact_id': id});
    if (!resp.success || resp.row == null) return null;
    return Contact.fromRow(resp.row!);
  }
}

final contactRepositoryProvider =
    Provider<ContactRepository>((ref) => ContactRepository(ref));

final contactsProvider =
    FutureProvider.autoDispose<List<Contact>>((ref) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(contactRepositoryProvider).list();
});

final contactProvider =
    FutureProvider.autoDispose.family<Contact?, int>((ref, id) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(contactRepositoryProvider).get(id);
});

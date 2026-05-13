import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import 'asset_model.dart';

class AssetRepository {
  final Ref ref;
  AssetRepository(this.ref);

  /// Fetches every asset by walking pages. ITFlow's read endpoint caps each
  /// response at the `limit` we send and only sorts ASC by id.
  Future<List<Asset>> list({
    int pageSize = 500,
    int maxItems = 50000,
    void Function(int loaded)? onProgress,
  }) async {
    final client = requireClient(ref);
    final all = <Asset>[];
    var offset = 0;
    while (offset < maxItems) {
      final resp = await client.get('assets', 'read', query: {
        'limit': pageSize,
        'offset': offset,
      });
      if (!resp.success) break;
      final rows = resp.rows;
      if (rows.isEmpty) break;
      all.addAll(rows.map(Asset.fromRow));
      onProgress?.call(all.length);
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  }

  Future<Asset?> get(int id) async {
    final client = requireClient(ref);
    final resp = await client.get('assets', 'read', query: {'asset_id': id});
    if (!resp.success || resp.row == null) return null;
    return Asset.fromRow(resp.row!);
  }

  /// Form fields use the friendly keys used in the form screen; we translate
  /// them to the prefixed POST keys that the API model file expects.
  Map<String, dynamic> _toPostBody(Map<String, dynamic> in_) {
    final out = <String, dynamic>{};
    void put(String src, String dst) {
      if (in_.containsKey(src)) out[dst] = in_[src];
    }

    put('name', 'asset_name');
    put('description', 'asset_description');
    put('type', 'asset_type');
    put('make', 'asset_make');
    put('model', 'asset_model');
    put('serial', 'asset_serial');
    put('os', 'asset_os');
    put('uri', 'asset_uri');
    put('uri_2', 'asset_uri_2');
    put('status', 'asset_status');
    put('ip', 'asset_ip');
    put('mac', 'asset_mac');
    put('notes', 'asset_notes');
    put('vendor', 'asset_vendor_id');
    put('vendor_id', 'asset_vendor_id');
    put('location', 'asset_location_id');
    put('location_id', 'asset_location_id');
    put('contact', 'asset_contact_id');
    put('contact_id', 'asset_contact_id');
    put('network', 'asset_network_id');
    put('network_id', 'asset_network_id');
    put('purchase_date', 'asset_purchase_date');
    put('warranty_expire', 'asset_warranty_expire');
    put('install_date', 'asset_install_date');
    // client_id is ignored by the asset create.php (taken from API key scope) —
    // pass through anyway in case ITFlow later allows it.
    put('client_id', 'client_id');
    return out;
  }

  Future<({int? id, String? error})> create(Map<String, dynamic> data) async {
    final client = requireClient(ref);
    final resp =
        await client.post('assets', 'create', body: _toPostBody(data));
    if (!resp.success) return (id: null, error: resp.message);
    return (id: resp.insertId, error: null);
  }

  Future<({bool ok, String? error})> update(
      int id, Map<String, dynamic> data) async {
    final client = requireClient(ref);
    final resp = await client.post(
      'assets',
      'update',
      body: {..._toPostBody(data), 'asset_id': id},
    );
    return (ok: resp.success, error: resp.message);
  }

  Future<({bool ok, String? error})> delete(int id) async {
    final client = requireClient(ref);
    final resp = await client.post('assets', 'delete', body: {'asset_id': id});
    return (ok: resp.success, error: resp.message);
  }
}

final assetRepositoryProvider =
    Provider<AssetRepository>((ref) => AssetRepository(ref));

class AssetLoadProgress extends Notifier<int> {
  @override
  int build() => 0;
  void set(int v) => state = v;
}

final assetLoadProgressProvider =
    NotifierProvider<AssetLoadProgress, int>(AssetLoadProgress.new);

final assetsProvider =
    FutureProvider.autoDispose<List<Asset>>((ref) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(assetRepositoryProvider).list(
        onProgress: (n) =>
            ref.read(assetLoadProgressProvider.notifier).set(n),
      );
});

final assetProvider =
    FutureProvider.autoDispose.family<Asset?, int>((ref, id) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(assetRepositoryProvider).get(id);
});

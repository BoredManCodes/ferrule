import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_response.dart';
import '../../core/api/providers.dart';
import 'credential_model.dart';

class CredentialRepository {
  final Ref ref;
  CredentialRepository(this.ref);

  Future<List<Credential>> fetchPage({
    required int offset,
    required int pageSize,
  }) async {
    final client = requireClient(ref);
    final resp = await client.get(
      'credentials',
      'read',
      query: {'limit': pageSize, 'offset': offset},
      includeDecrypt: true,
    );
    if (!resp.success) {
      throw ApiException(resp.message ?? 'Failed to load credentials');
    }
    return resp.rows.map(Credential.fromRow).toList();
  }

  Future<Credential?> get(int id) async {
    final client = requireClient(ref);
    final resp = await client.get(
      'credentials',
      'read',
      query: {'credential_id': id},
      includeDecrypt: true,
    );
    if (!resp.success || resp.row == null) return null;
    return Credential.fromRow(resp.row!);
  }

  Map<String, dynamic> _toPostBody(Map<String, dynamic> in_) {
    final out = <String, dynamic>{};
    void put(String src, String dst) {
      if (in_.containsKey(src)) out[dst] = in_[src];
    }

    put('name', 'credential_name');
    put('description', 'credential_description');
    put('uri', 'credential_uri');
    put('uri_2', 'credential_uri_2');
    put('username', 'credential_username');
    put('password', 'credential_password');
    put('otp_secret', 'credential_otp_secret');
    put('note', 'credential_note');
    put('favorite', 'credential_favorite');
    put('contact_id', 'credential_contact_id');
    put('vendor_id', 'credential_vendor_id');
    put('asset_id', 'credential_asset_id');
    put('software_id', 'credential_software_id');
    put('client_id', 'client_id');
    return out;
  }

  Future<({int? id, String? error})> create(Map<String, dynamic> data) async {
    final client = requireClient(ref);
    final resp = await client.post(
      'credentials',
      'create',
      body: _toPostBody(data),
      includeDecrypt: true,
    );
    if (!resp.success) return (id: null, error: resp.message);
    return (id: resp.insertId, error: null);
  }

  Future<({bool ok, String? error})> update(
      int id, Map<String, dynamic> data) async {
    final client = requireClient(ref);
    final resp = await client.post(
      'credentials',
      'update',
      body: {..._toPostBody(data), 'credential_id': id},
      includeDecrypt: true,
    );
    return (ok: resp.success, error: resp.message);
  }
}

final credentialRepositoryProvider =
    Provider<CredentialRepository>((ref) => CredentialRepository(ref));

class CredentialsListState {
  final List<Credential> items;
  final bool loadingMore;
  final bool allLoaded;
  final String? loadMoreError;

  const CredentialsListState({
    required this.items,
    this.loadingMore = false,
    this.allLoaded = false,
    this.loadMoreError,
  });

  CredentialsListState copyWith({
    List<Credential>? items,
    bool? loadingMore,
    bool? allLoaded,
    String? loadMoreError,
    bool clearError = false,
  }) {
    return CredentialsListState(
      items: items ?? this.items,
      loadingMore: loadingMore ?? this.loadingMore,
      allLoaded: allLoaded ?? this.allLoaded,
      loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class CredentialsListNotifier extends AsyncNotifier<CredentialsListState> {
  static const int pageSize = 50;
  static const int maxItems = 50000;

  bool _backgroundLoading = false;
  bool _disposed = false;

  @override
  Future<CredentialsListState> build() async {
    ref.onDispose(() => _disposed = true);
    await ref.watch(credentialsProvider.future);
    final repo = ref.read(credentialRepositoryProvider);
    final batch = await repo.fetchPage(offset: 0, pageSize: pageSize);
    ref.read(credentialLoadProgressProvider.notifier).set(batch.length);
    final done = batch.length < pageSize;
    if (!done) {
      // Start background loading after this build() commits its state.
      Future<void>(_loadRemaining);
    }
    return CredentialsListState(
      items: batch,
      allLoaded: done,
      loadingMore: !done,
    );
  }

  Future<void> _loadRemaining() async {
    if (_disposed || _backgroundLoading) return;
    final initial = state.value;
    if (initial == null || initial.allLoaded) return;
    _backgroundLoading = true;
    state = AsyncValue.data(
        initial.copyWith(loadingMore: true, clearError: true));

    try {
      var working = state.value!.items;
      while (!_disposed && working.length < maxItems) {
        final repo = ref.read(credentialRepositoryProvider);
        final batch = await repo.fetchPage(
            offset: working.length, pageSize: pageSize);
        if (_disposed) return;
        if (batch.isEmpty) {
          state = AsyncValue.data(
              state.value!.copyWith(allLoaded: true, loadingMore: false));
          return;
        }
        working = [...working, ...batch];
        final done = batch.length < pageSize;
        state = AsyncValue.data(state.value!.copyWith(
          items: working,
          allLoaded: done,
          loadingMore: !done,
        ));
        ref.read(credentialLoadProgressProvider.notifier).set(working.length);
        if (done) return;
      }
    } catch (e) {
      if (!_disposed && state.value != null) {
        state = AsyncValue.data(state.value!.copyWith(
          loadingMore: false,
          loadMoreError: e.toString(),
        ));
      }
    } finally {
      _backgroundLoading = false;
    }
  }

  Future<void> retryMore() async {
    if (_backgroundLoading) return;
    if (state.value == null || state.value!.allLoaded) return;
    return _loadRemaining();
  }
}

class CredentialLoadProgress extends Notifier<int> {
  @override
  int build() => 0;
  void set(int v) => state = v;
}

final credentialLoadProgressProvider =
    NotifierProvider<CredentialLoadProgress, int>(CredentialLoadProgress.new);

final credentialsListProvider = AsyncNotifierProvider.autoDispose<
    CredentialsListNotifier,
    CredentialsListState>(CredentialsListNotifier.new);

final credentialProvider =
    FutureProvider.autoDispose.family<Credential?, int>((ref, id) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(credentialRepositoryProvider).get(id);
});

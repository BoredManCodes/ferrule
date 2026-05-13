import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_store.dart';
import 'itflow_client.dart';
import 'itflow_web_client.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

class CredentialsController extends AsyncNotifier<Credentials?> {
  @override
  Future<Credentials?> build() async {
    final store = ref.read(secureStoreProvider);
    return store.read();
  }

  Future<void> save(Credentials c) async {
    final store = ref.read(secureStoreProvider);
    await store.save(c);
    state = AsyncValue.data(c);
  }

  Future<void> logout() async {
    final store = ref.read(secureStoreProvider);
    await store.clear();
    state = const AsyncValue.data(null);
  }

  Future<void> setDecryptPassword(String? pw) async {
    final current = state.value;
    if (current == null) return;
    final updated = current.copyWith(decryptPassword: pw);
    final store = ref.read(secureStoreProvider);
    await store.save(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> setWebCredentials({String? email, String? password}) async {
    final current = state.value;
    if (current == null) return;
    final updated =
        current.copyWith(webEmail: email ?? '', webPassword: password ?? '');
    final store = ref.read(secureStoreProvider);
    await store.save(updated);
    state = AsyncValue.data(updated);
  }
}

final credentialsProvider =
    AsyncNotifierProvider<CredentialsController, Credentials?>(
        CredentialsController.new);

final itflowClientProvider = Provider<ItflowClient?>((ref) {
  final creds = ref.watch(credentialsProvider).value;
  if (creds == null) return null;
  return ItflowClient(
    baseUrl: creds.instanceUrl,
    apiKey: creds.apiKey,
    decryptPassword: creds.decryptPassword,
  );
});

ItflowClient requireClient(Ref ref) {
  final c = ref.read(itflowClientProvider);
  if (c == null) {
    throw StateError('Not authenticated');
  }
  return c;
}

final itflowWebClientProvider = Provider<ItflowWebClient?>((ref) {
  final creds = ref.watch(credentialsProvider).value;
  if (creds == null || !creds.hasWebCreds) return null;
  return ItflowWebClient(
    baseUrl: creds.instanceUrl,
    email: creds.webEmail!,
    password: creds.webPassword!,
  );
});

ItflowWebClient requireWebClient(Ref ref) {
  final c = ref.read(itflowWebClientProvider);
  if (c == null) {
    throw StateError(
        'Web credentials not set. Add agent email + password in Settings to log time.');
  }
  return c;
}

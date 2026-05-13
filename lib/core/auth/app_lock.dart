import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../api/providers.dart';
import '../settings/app_settings.dart';

final localAuthProvider = Provider<LocalAuthentication>((_) {
  return LocalAuthentication();
});

/// True if the device has *any* auth method we can use as a fallback —
/// biometrics, PIN, pattern or password. Used to decide whether the
/// "Require unlock" toggle should even be offered.
final canAuthenticateProvider = FutureProvider<bool>((ref) async {
  final auth = ref.read(localAuthProvider);
  try {
    return await auth.isDeviceSupported();
  } catch (_) {
    return false;
  }
});

class AppLockNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Drop back to locked when credentials are cleared so a fresh re-login
    // on the same install still has to authenticate.
    ref.listen(credentialsProvider, (_, next) {
      if (next.value == null) state = false;
    });
    return false;
  }

  void markUnlocked() {
    if (state) return;
    state = true;
  }

  void lock() => state = false;
}

/// In-memory: true means the user has already passed the gate this session.
/// Not persisted — every cold start re-locks.
final appLockProvider =
    NotifierProvider<AppLockNotifier, bool>(AppLockNotifier.new);

/// Should the router send the user to /lock right now?
final lockRequiredProvider = Provider<bool>((ref) {
  final settings = ref.watch(appSettingsProvider).value;
  if (settings == null || !settings.requireDeviceUnlock) return false;
  final creds = ref.watch(credentialsProvider).value;
  if (creds == null) return false;
  return !ref.watch(appLockProvider);
});

Future<bool> promptDeviceUnlock(
  LocalAuthentication auth, {
  required String reason,
}) async {
  try {
    return await auth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        // stickyAuth=false: the system biometric prompt pauses the activity,
        // and sticky mode caused the prompt to re-fire on resume — we'd
        // rather have a single shot and let the user retry the button.
        stickyAuth: false,
        biometricOnly: false,
      ),
    );
  } catch (_) {
    return false;
  }
}

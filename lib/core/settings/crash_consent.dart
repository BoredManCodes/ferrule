import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sentry/sentry_config.dart';

enum CrashConsent { unset, optedIn, optedOut }

const _kCrashConsent = 'pref.crashConsent';

Future<CrashConsent> readCrashConsentRaw() async {
  final p = await SharedPreferences.getInstance();
  switch (p.getString(_kCrashConsent)) {
    case 'in':
      return CrashConsent.optedIn;
    case 'out':
      return CrashConsent.optedOut;
    default:
      return CrashConsent.unset;
  }
}

Future<void> initSentryWithDefaults() async {
  await SentryFlutter.init((options) {
    options.dsn = sentryDsn;
    options.environment = sentryEnv;
    options.sendDefaultPii = false;
    options.tracesSampleRate = 0.1;
  });
}

class CrashConsentNotifier extends AsyncNotifier<CrashConsent> {
  @override
  Future<CrashConsent> build() => readCrashConsentRaw();

  Future<void> _persist(CrashConsent c) async {
    final p = await SharedPreferences.getInstance();
    switch (c) {
      case CrashConsent.optedIn:
        await p.setString(_kCrashConsent, 'in');
        break;
      case CrashConsent.optedOut:
        await p.setString(_kCrashConsent, 'out');
        break;
      case CrashConsent.unset:
        await p.remove(_kCrashConsent);
        break;
    }
    state = AsyncValue.data(c);
  }

  Future<void> optIn() async {
    await _persist(CrashConsent.optedIn);
    if (!sentryConfigured) return;
    if (Sentry.isEnabled) return;
    await initSentryWithDefaults();
  }

  Future<void> optOut() async {
    await _persist(CrashConsent.optedOut);
    if (Sentry.isEnabled) {
      await Sentry.close();
    }
  }
}

final crashConsentProvider =
    AsyncNotifierProvider<CrashConsentNotifier, CrashConsent>(
        CrashConsentNotifier.new);

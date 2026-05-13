import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/sentry/sentry_config.dart';
import 'core/settings/crash_consent.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (sentryConfigured) {
    final consent = await readCrashConsentRaw();
    if (consent == CrashConsent.optedIn) {
      await initSentryWithDefaults();
    }
  }

  runApp(const ProviderScope(child: ItflowApp()));
}

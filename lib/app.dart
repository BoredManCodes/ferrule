import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/providers.dart';
import 'core/router.dart';
import 'core/settings/app_settings.dart';
import 'core/storage/secure_store.dart';
import 'core/theme.dart';

class FerruleApp extends ConsumerStatefulWidget {
  const FerruleApp({super.key});

  @override
  ConsumerState<FerruleApp> createState() => _FerruleAppState();
}

class _FerruleAppState extends ConsumerState<FerruleApp> {
  Credentials? _lastSeenCreds;

  @override
  void initState() {
    super.initState();
    // After login, opportunistically scrape the ITFlow instance's accent color
    // so the app re-skins to match. Only when the user has chosen "auto".
    ref.listenManual<AsyncValue<Credentials?>>(credentialsProvider,
        (prev, next) {
      final c = next.value;
      if (c != null && c.hasWebCreds && c != _lastSeenCreds) {
        _lastSeenCreds = c;
        _maybeRefreshAccent();
      } else if (c == null) {
        _lastSeenCreds = null;
      }
    });
  }

  Future<void> _maybeRefreshAccent() async {
    final settings = ref.read(appSettingsProvider).value;
    if (settings == null) return;
    final web = ref.read(itflowWebClientProvider);
    if (web == null) return;
    try {
      final b = await web.fetchInstanceBranding();
      // Accent is auto-applied only if the user has chosen "auto" — but we
      // cache it regardless so toggling auto later works without re-fetch.
      if (b.accent != null && settings.accentMode == 'auto') {
        await ref
            .read(appSettingsProvider.notifier)
            .setCachedInstanceAccent(b.accent!);
      }
      if (b.name != null) {
        await ref
            .read(appSettingsProvider.notifier)
            .setCachedInstanceName(b.name!);
      }
    } catch (_) {/* non-fatal */}
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final seed = settings.effectiveSeedColor;

    final ThemeData light = AppTheme.light(seed: seed);
    final ThemeData dark = settings.themeMode == 'oled'
        ? AppTheme.oled(seed: seed)
        : AppTheme.dark(seed: seed);

    final ThemeMode themeMode = switch (settings.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'oled' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return MaterialApp.router(
      title: settings.effectiveTitle,
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

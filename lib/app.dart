import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/itflow_web_client.dart';
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
      if (c != null && c != _lastSeenCreds) {
        _lastSeenCreds = c;
        _maybeRefreshBranding();
      } else if (c == null) {
        _lastSeenCreds = null;
      }
    });
  }

  Future<void> _maybeRefreshBranding() async {
    final settings = ref.read(appSettingsProvider).value;
    if (settings == null) return;
    final creds = ref.read(credentialsProvider).value;
    if (creds == null) return;
    // Use the configured web client if web creds are set; otherwise build a
    // throwaway one with empty creds so we can still scrape the public
    // login.php (company name lives there and the agent-page lookup that
    // needs auth will just fail silently inside fetchInstanceBranding).
    final web = ref.read(itflowWebClientProvider) ??
        ItflowWebClient(
          baseUrl: creds.instanceUrl,
          email: '',
          password: '',
        );
    try {
      final b = await web.fetchInstanceBranding();
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

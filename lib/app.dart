import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/itflow_web_client.dart';
import 'core/api/providers.dart';
import 'core/auth/api_key_provisioning.dart';
import 'core/auth/mfa_bridge.dart';
import 'core/auth/mfa_prompt_dialog.dart';
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
    MfaBridge.prompt = ({required String email, String? error}) async {
      final ctx =
          ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return null;
      return showMfaPromptDialog(ctx, email: email, error: error);
    };
    // After login, opportunistically scrape the ITFlow instance's accent color
    // so the app re-skins to match. Only when the user has chosen "auto".
    ref.listenManual<AsyncValue<Credentials?>>(credentialsProvider,
        (prev, next) {
      final c = next.value;
      if (c != null && c != _lastSeenCreds) {
        _lastSeenCreds = c;
        _onNewCredentials(c);
      } else if (c == null) {
        _lastSeenCreds = null;
      }
    });
  }

  /// Runs after every credentials change. Sequenced (branding then
  /// rotation, rather than fired concurrently) so a fresh login for the
  /// accent scrape doesn't race the login that just finished provisioning
  /// the API key.
  Future<void> _onNewCredentials(Credentials c) async {
    await _maybeRefreshBranding();
    await _maybeRotateApiKey(c);
  }

  /// Opportunistically rotates the app-created API key when it's nearing
  /// expiry. No-op for manually-pasted keys or when nothing's due yet; see
  /// [rotateApiKeyIfNeeded].
  Future<void> _maybeRotateApiKey(Credentials creds) async {
    final updated = await rotateApiKeyIfNeeded(creds);
    if (updated == null) return;
    // The rotation ran against a snapshot; only persist if the user hasn't
    // changed credentials again in the meantime.
    if (ref.read(credentialsProvider).value != creds) return;
    // Set before saving: `save()` notifies this same listener synchronously,
    // and the freshly-rotated key won't be due again, so this just avoids a
    // redundant recursive rotation/branding check.
    _lastSeenCreds = updated;
    await ref.read(credentialsProvider.notifier).save(updated);
  }

  Future<void> _maybeRefreshBranding() async {
    // One retry: this runs automatically right after login (often right on
    // the heels of the API-key provisioning login), so a single transient
    // failure there would otherwise leave the user stuck with the default
    // theme until they found the manual "Re-detect from ITFlow" button.
    final ok = await _tryRefreshBranding();
    if (!ok) {
      await Future.delayed(const Duration(seconds: 3));
      await _tryRefreshBranding();
    }
  }

  /// Returns true if the branding fetch completed without throwing (not
  /// whether it actually found an accent/name — an instance with no
  /// detectable accent class still "succeeds").
  Future<bool> _tryRefreshBranding() async {
    final settings = ref.read(appSettingsProvider).value;
    if (settings == null) return false;
    final creds = ref.read(credentialsProvider).value;
    if (creds == null) return false;
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
      return true;
    } catch (_) {
      return false;
    }
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

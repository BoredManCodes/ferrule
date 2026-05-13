import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/providers.dart';
import '../../core/auth/app_lock.dart';
import '../../core/sentry/sentry_config.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/crash_consent.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(credentialsProvider).value;
    final settings = ref.watch(appSettingsProvider).value ?? const AppSettings();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Display name'),
            subtitle: Text(
              settings.displayName != null && settings.displayName!.isNotEmpty
                  ? settings.displayName!
                  : settings.cachedInstanceName != null
                      ? '${settings.cachedInstanceName} (from ITFlow)'
                      : 'ITFlow',
            ),
            trailing: TextButton(
              onPressed: () async {
                final name = await showDialog<String>(
                  context: context,
                  builder: (_) => _TextDialog(
                    title: 'Display name',
                    initial: settings.displayName ?? '',
                    helper: settings.cachedInstanceName != null
                        ? 'Leave empty to use "${settings.cachedInstanceName}" from your ITFlow instance. Launcher icon & name stay as ITFlow.'
                        : 'Shown in app titles. Launcher icon & name stay as ITFlow.',
                  ),
                );
                if (name != null) {
                  await ref
                      .read(appSettingsProvider.notifier)
                      .setDisplayName(name.isEmpty ? null : name);
                }
              },
              child: const Text('Change'),
            ),
          ),
          _AccentTiles(
              settings: settings,
              web: ref.watch(itflowWebClientProvider) != null),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Theme',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'system',
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('System')),
                ButtonSegment(
                    value: 'light',
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light')),
                ButtonSegment(
                    value: 'dark',
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark')),
                ButtonSegment(
                    value: 'oled',
                    icon: Icon(Icons.contrast),
                    label: Text('OLED')),
              ],
              selected: {settings.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => ref
                  .read(appSettingsProvider.notifier)
                  .setThemeMode(s.first),
            ),
          ),
          const Divider(),
          const _SectionHeader('Connection'),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Instance'),
            subtitle: Text(creds?.instanceUrl ?? '—'),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('API Key'),
            subtitle: const Text('Stored securely on device'),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Vault Decrypt Password'),
            subtitle: Text((creds?.decryptPassword ?? '').isEmpty
                ? 'Not set — credentials are locked'
                : 'Set'),
            trailing: TextButton(
              onPressed: () async {
                final pw = await showDialog<String>(
                  context: context,
                  builder: (_) => _SecretDialog(
                    title: 'Vault Decrypt Password',
                    initial: creds?.decryptPassword ?? '',
                  ),
                );
                if (pw != null) {
                  await ref
                      .read(credentialsProvider.notifier)
                      .setDecryptPassword(pw.isEmpty ? null : pw);
                }
              },
              child: const Text('Change'),
            ),
          ),
          const Divider(),
          const _SectionHeader('Web Session (for Labour Timer)'),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Agent Email'),
            subtitle: Text(creds?.webEmail?.isNotEmpty == true
                ? creds!.webEmail!
                : 'Not set — time submission disabled'),
            trailing: TextButton(
              onPressed: () async {
                final email = await showDialog<String>(
                  context: context,
                  builder: (_) => _SecretDialog(
                    title: 'Agent Email',
                    initial: creds?.webEmail ?? '',
                    obscure: false,
                  ),
                );
                if (email != null) {
                  await ref
                      .read(credentialsProvider.notifier)
                      .setWebCredentials(
                        email: email,
                        password: creds?.webPassword,
                      );
                }
              },
              child: const Text('Change'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Agent Password'),
            subtitle: Text((creds?.webPassword ?? '').isEmpty
                ? 'Not set'
                : 'Set'),
            trailing: TextButton(
              onPressed: () async {
                final pw = await showDialog<String>(
                  context: context,
                  builder: (_) => _SecretDialog(
                    title: 'Agent Password',
                    initial: creds?.webPassword ?? '',
                  ),
                );
                if (pw != null) {
                  await ref
                      .read(credentialsProvider.notifier)
                      .setWebCredentials(
                        email: creds?.webEmail,
                        password: pw,
                      );
                }
              },
              child: const Text('Change'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'These credentials drive the ITFlow web UI to log time on tickets. '
              '2FA on this account is not supported.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),
          const _SectionHeader('Security'),
          _RequireUnlockTile(),
          if (sentryConfigured) ...[
            const Divider(),
            const _SectionHeader('Privacy'),
            _CrashConsentTile(),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text(
                'Built by Trent Buckley • Border Tech Solutions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              useRootNavigator: true,
              builder: (_) => const _AboutDialog(),
            ),
          ),
          ListTile(
            leading: Icon(Icons.logout,
                color: Theme.of(context).colorScheme.error),
            title: Text('Sign out',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () async {
              // useRootNavigator: true keeps the dialog above the shell so it
              // isn't stranded when we navigate to /setup after logout.
              final confirm = await showDialog<bool>(
                context: context,
                useRootNavigator: true,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: const Text(
                      'Your API key, vault password, and web credentials will be removed from this device.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel')),
                    FilledButton.tonal(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              await ref.read(credentialsProvider.notifier).logout();
              if (!context.mounted) return;
              // Bypass the refresh-listener redirect — go directly. This is
              // reliable regardless of where in the shell we were.
              context.go('/setup');
            },
          ),
        ],
      ),
    );
  }
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shield_outlined,
                color: scheme.onPrimaryContainer, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('ITFlow Client')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mobile companion for your ITFlow instance.'),
          const SizedBox(height: 16),
          Text(
            'BUILT BY',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          const Text('Trent Buckley'),
          const SizedBox(height: 12),
          Text(
            'A PROJECT BY',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () =>
                launchUrl(Uri.parse('https://bordertechsolutions.com.au')),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Border Tech Solutions',
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 14, color: scheme.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.favorite,
                        size: 14, color: Colors.pinkAccent),
                    const SizedBox(width: 6),
                    Text(
                      'WITH MASSIVE THANKS TO',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'The ITFlow developers and community for building and maintaining the open-source platform this app talks to.',
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => launchUrl(
                      Uri.parse('https://github.com/itflow-org/itflow')),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'github.com/itflow-org/itflow',
                          style: TextStyle(
                            color: scheme.primary,
                            decoration: TextDecoration.underline,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.open_in_new,
                            size: 12, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _AccentTiles extends ConsumerWidget {
  final AppSettings settings;
  final bool web;
  const _AccentTiles({required this.settings, required this.web});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuto = settings.accentMode == 'auto';
    final current = settings.effectiveSeedColor;
    final subtitleParts = <String>[];
    if (isAuto) {
      subtitleParts.add('Auto');
      if (settings.cachedInstanceAccent != null) {
        subtitleParts.add('${settings.cachedInstanceAccent} (from ITFlow)');
      } else if (web) {
        subtitleParts.add('detecting…');
      } else {
        subtitleParts.add('using default — set Web Session credentials to detect');
      }
    } else {
      subtitleParts
          .add('Manual: ${settings.manualAccentColor ?? "indigo (default)"}');
    }
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: current, shape: BoxShape.circle),
          ),
          title: const Text('Accent color'),
          subtitle: Text(subtitleParts.join(' · ')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Match ITFlow')),
              ButtonSegment(value: 'manual', label: Text('Manual')),
            ],
            selected: {settings.accentMode},
            onSelectionChanged: (s) => ref
                .read(appSettingsProvider.notifier)
                .setAccentMode(s.first),
          ),
        ),
        if (isAuto)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: web
                    ? () async {
                        final c =
                            ref.read(itflowWebClientProvider);
                        if (c == null) return;
                        final accent = await c.fetchInstanceAccent();
                        if (accent != null) {
                          await ref
                              .read(appSettingsProvider.notifier)
                              .setCachedInstanceAccent(accent);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(accent == null
                                  ? 'Could not detect instance accent.'
                                  : 'Detected accent: $accent'),
                            ),
                          );
                        }
                      }
                    : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Re-detect from ITFlow'),
              ),
            ),
          ),
        if (!isAuto)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in adminLteAccents.entries)
                  GestureDetector(
                    onTap: () => ref
                        .read(appSettingsProvider.notifier)
                        .setManualAccent(entry.key),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: entry.value,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: settings.manualAccentColor == entry.key
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: settings.manualAccentColor == entry.key
                          ? Icon(
                              Icons.check,
                              size: 18,
                              color: ThemeData.estimateBrightnessForColor(
                                          entry.value) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RequireUnlockTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final canAuth = ref.watch(canAuthenticateProvider).value ?? false;
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: const Text('Require unlock on launch'),
      subtitle: Text(
        !canAuth
            ? 'Set up a screen lock or biometric on this device to enable.'
            : settings.requireDeviceUnlock
                ? 'Biometric or device PIN required when the app starts.'
                : 'App opens straight to your account.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      value: settings.requireDeviceUnlock && canAuth,
      onChanged: !canAuth
          ? null
          : (v) async {
              final notifier = ref.read(appSettingsProvider.notifier);
              if (v) {
                final ok = await promptDeviceUnlock(
                  ref.read(localAuthProvider),
                  reason: 'Confirm to enable launch unlock',
                );
                if (!ok) return;
                await notifier.setRequireDeviceUnlock(true);
                // The user just authenticated to enable it — don't immediately
                // prompt again on the very next router refresh.
                ref.read(appLockProvider.notifier).markUnlocked();
              } else {
                await notifier.setRequireDeviceUnlock(false);
              }
            },
    );
  }
}

class _CrashConsentTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(crashConsentProvider).value ?? CrashConsent.unset;
    final on = consent == CrashConsent.optedIn;
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      secondary: const Icon(Icons.bug_report_outlined),
      title: const Text('Send crash reports'),
      subtitle: Text(
        on
            ? 'Anonymous crash reports help fix bugs. No PII, no ITFlow data.'
            : 'Off — no crash reports are sent.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      value: on,
      onChanged: (v) async {
        final notifier = ref.read(crashConsentProvider.notifier);
        if (v) {
          await notifier.optIn();
        } else {
          await notifier.optOut();
        }
      },
    );
  }
}

class _TextDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String? helper;
  const _TextDialog({
    required this.title,
    required this.initial,
    this.helper,
  });

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.title,
          helperText: widget.helper,
          helperMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SecretDialog extends StatefulWidget {
  final String title;
  final String initial;
  final bool obscure;
  const _SecretDialog({
    required this.title,
    required this.initial,
    this.obscure = true,
  });

  @override
  State<_SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<_SecretDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  late bool _obscure = widget.obscure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        obscureText: _obscure,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.title,
          suffixIcon: widget.obscure
              ? IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )
              : null,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

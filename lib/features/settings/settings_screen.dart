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
          const Divider(),
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
                        ? 'Leave empty to use "${settings.cachedInstanceName}" from your ITFlow instance. Launcher icon & name stay as Ferrule.'
                        : 'Shown in app titles. Launcher icon & name stay as Ferrule.',
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
          const Divider(),
          const _SectionHeader('Privacy'),
          if (sentryConfigured) _CrashConsentTile(),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy policy'),
            subtitle: const Text('How Ferrule handles your data'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/privacy'),
          ),
          const Divider(),
          const _SectionHeader('Support'),
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Get help'),
            subtitle:
                const Text('Different problems need different inboxes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              useRootNavigator: true,
              builder: (_) => const _SupportDialog(),
            ),
          ),
          const Divider(),
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
          const Expanded(child: Text('Ferrule — Client for ITFlow')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mobile companion for your ITFlow instance.'),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'ferrule',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                TextSpan(
                  text:
                      ' /ˈfɛrəl/ — the small metal band that binds a tool together. '
                      'This client does the same for your ITFlow workflow.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => launchUrl(
                Uri.parse('https://donate.stripe.com/9B65kE1zZdJf08d51S14400'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.favorite_outline, size: 16),
              label: const Text('Support development'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ferrule is free and unaffiliated with ITFlow. If it saves you time, a small tip keeps it maintained.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
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

class _SupportDialog extends StatelessWidget {
  const _SupportDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.support_agent_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('Where to get help')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ferrule talks to your ITFlow instance over the network. '
              'That means problems generally fall into one of two camps, '
              'and they go to different places.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _SupportCard(
              icon: Icons.phone_iphone_outlined,
              accent: scheme.primary,
              title: 'A problem with the app',
              ours: true,
              examples: const [
                'A button does nothing or shows a Flutter error.',
                'A screen looks broken or a list never loads.',
                'The app crashed.',
                'A feature is missing or behaves unexpectedly.',
                'Layout looks wrong on your phone.',
              ],
              actionLabel: 'Email Border Tech Solutions',
              actionIcon: Icons.mail_outline,
              onAction: () => launchUrl(Uri.parse(
                  'mailto:support@bordertechsolutions.com.au?subject=Ferrule%20app%20issue')),
              tail:
                  'Include what you tapped, what you expected, and what '
                  'happened. A screenshot helps. Mention your ITFlow version '
                  'if you know it.',
            ),
            const SizedBox(height: 12),
            _SupportCard(
              icon: Icons.dns_outlined,
              accent: scheme.tertiary,
              title: 'A problem with ITFlow itself',
              ours: false,
              examples: const [
                'You can\'t sign into the ITFlow website either.',
                'Data is missing or wrong on the server.',
                'The server is slow, returning 500 errors, or down.',
                'An ITFlow feature behaves the same in the web UI as in the app.',
                'You need help with ITFlow configuration, permissions, or '
                    'plugins.',
              ],
              actionLabel: 'Open ITFlow on GitHub',
              actionIcon: Icons.open_in_new,
              onAction: () => launchUrl(
                  Uri.parse('https://github.com/itflow-org/itflow'),
                  mode: LaunchMode.externalApplication),
              tail:
                  'ITFlow is an independent open-source project. Their '
                  'community and maintainers are best placed to help with '
                  'server-side issues; Border Tech Solutions doesn\'t '
                  'maintain ITFlow itself.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.help_outline,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Not sure which? A quick test: open your ITFlow '
                      'instance in a browser and try the same thing. If it '
                      'fails there too, it\'s an ITFlow issue. If it only '
                      'fails in the app, it\'s ours.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

class _SupportCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final bool ours;
  final List<String> examples;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final String tail;

  const _SupportCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.ours,
    required this.examples,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.tail,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  ours ? 'Our area' : 'ITFlow\'s area',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: accent, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• $e',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.4,
                    ),
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: onAction,
              icon: Icon(actionIcon, size: 16),
              label: Text(actionLabel),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}

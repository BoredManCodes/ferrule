import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/providers.dart';
import '../../core/auth/app_lock.dart';
import '../../core/settings/app_settings.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _busy = false;
  bool _autoPrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prompt(auto: true));
  }

  Future<void> _prompt({bool auto = false}) async {
    if (_busy) return;
    // Bail out if we're already unlocked — guards against a stale State being
    // remounted on top of an unlocked session and re-opening the system sheet.
    if (ref.read(appLockProvider)) return;
    // Only fire automatically once per mount so a cancelled prompt doesn't
    // immediately re-open the system sheet in a loop.
    if (auto && _autoPrompted) return;
    _autoPrompted = true;
    setState(() => _busy = true);
    final auth = ref.read(localAuthProvider);
    final ok = await promptDeviceUnlock(auth, reason: 'Unlock Ferrule');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.read(appLockProvider.notifier).markUnlocked();
      // The router's refreshListenable should pick this up, but go directly
      // so we're not at the mercy of refresh timing.
      if (mounted) context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title =
        ref.watch(appSettingsProvider).value?.effectiveTitle ?? 'ITFlow';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_outline,
                      size: 32, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 20),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Locked',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _prompt(),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await ref
                              .read(credentialsProvider.notifier)
                              .logout();
                        },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

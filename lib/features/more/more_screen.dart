import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/ui_prefs.dart';
import '../onboarding/tips.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = (ref.watch(uiPrefsProvider).value ?? const UiPrefs()).moreDests;
    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        actions: [
          IconButton(
            tooltip: 'Customize',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/settings/navigation'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        children: [
          const FirstVisitTip(
            id: 'more.customize',
            icon: Icons.tune,
            text:
                'Want Contacts or Trips on the bottom bar instead? Tap the sliders above to move things between the bar and this list, and to reorder them.',
          ),
          for (final item in items) ...[
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => item.path == '/'
                  ? context.go('/')
                  : context.push(item.path),
            ),
            const Divider(height: 1),
          ],
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Customize navigation'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/navigation'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

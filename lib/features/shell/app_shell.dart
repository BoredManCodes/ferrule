import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/ui_prefs.dart';
import '../timer/timer_banner.dart';

const _more = NavDest('/more', Icons.apps_outlined, Icons.apps, 'More');

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  /// The bar item the location belongs to, or More for anything reached
  /// from there (sub-pages, settings, items not on the bar).
  int _indexFor(String location, List<NavDest> dests) {
    for (var i = 0; i < dests.length - 1; i++) {
      final p = dests[i].path;
      if (p == '/' ? location == '/' : (location == p || location.startsWith('$p/'))) {
        return i;
      }
    }
    return dests.length - 1;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(uiPrefsProvider).value ?? const UiPrefs();
    final dests = [...prefs.barDests, _more];
    final location = GoRouterState.of(context).uri.path;
    final idx = _indexFor(location, dests);
    final isWide = MediaQuery.of(context).size.width >= 720;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: idx,
              onDestinationSelected: (i) => context.go(dests[i].path),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in dests)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(_short(d.label)),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  const TimerBanner(),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          const TimerBanner(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => context.go(dests[i].path),
        destinations: [
          for (final d in dests)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: _short(d.label),
            ),
        ],
      ),
    );
  }

  // Bar labels have little room.
  static String _short(String label) => switch (label) {
        'Labour Timer' => 'Timer',
        'Agent Banners' => 'Banners',
        'Certificates' => 'Certs',
        _ => label,
      };
}

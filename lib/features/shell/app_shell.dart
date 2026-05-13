import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../timer/timer_banner.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _destinations = [
    _NavItem('/', Icons.dashboard_outlined, Icons.dashboard, 'Home'),
    _NavItem('/tickets', Icons.confirmation_number_outlined,
        Icons.confirmation_number, 'Tickets'),
    _NavItem(
        '/assets', Icons.devices_other_outlined, Icons.devices_other, 'Assets'),
    _NavItem('/credentials', Icons.vpn_key_outlined, Icons.vpn_key, 'Vault'),
    _NavItem('/more', Icons.apps_outlined, Icons.apps, 'More'),
  ];

  int _indexFor(String location) {
    if (location == '/') return 0;
    // Check specific tabs (skip Home and the final "More" catch-all).
    for (var i = 1; i < _destinations.length - 1; i++) {
      if (location.startsWith(_destinations[i].path)) return i;
    }
    // Any sub-route the bottom-nav doesn't explicitly map (clients, contacts,
    // documents, settings, etc.) is reached via the "More" tab — keep it lit.
    return _destinations.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final idx = _indexFor(location);
    final isWide = MediaQuery.of(context).size.width >= 720;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: idx,
              onDestinationSelected: (i) => context.go(_destinations[i].path),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
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
        onDestinationSelected: (i) => context.go(_destinations[i].path),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.path, this.icon, this.selectedIcon, this.label);
}

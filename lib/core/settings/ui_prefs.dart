import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A place the app can take you: on the bottom bar or listed under More.
class NavDest {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const NavDest(this.path, this.icon, this.selectedIcon, this.label);
}

/// Every destination, in the default order. The bottom bar holds up to
/// [maxBarItems] of them plus More; the rest are listed under More.
const navCatalog = <NavDest>[
  NavDest('/', Icons.dashboard_outlined, Icons.dashboard, 'Home'),
  NavDest('/tickets', Icons.confirmation_number_outlined,
      Icons.confirmation_number, 'Tickets'),
  NavDest('/assets', Icons.devices_other_outlined, Icons.devices_other, 'Assets'),
  NavDest('/credentials', Icons.vpn_key_outlined, Icons.vpn_key, 'Vault'),
  NavDest('/timer', Icons.timer_outlined, Icons.timer, 'Labour Timer'),
  NavDest('/trips', Icons.route_outlined, Icons.route, 'Trips'),
  NavDest('/clients', Icons.business_outlined, Icons.business, 'Clients'),
  NavDest('/contacts', Icons.contacts_outlined, Icons.contacts, 'Contacts'),
  NavDest('/documents', Icons.description_outlined, Icons.description, 'Documents'),
  NavDest('/domains', Icons.dns_outlined, Icons.dns, 'Domains'),
  NavDest('/locations', Icons.location_on_outlined, Icons.location_on, 'Locations'),
  NavDest('/networks', Icons.lan_outlined, Icons.lan, 'Networks'),
  NavDest('/software', Icons.apps_outlined, Icons.apps, 'Software'),
  NavDest('/vendors', Icons.store_outlined, Icons.store, 'Vendors'),
  NavDest('/products', Icons.shopping_bag_outlined, Icons.shopping_bag, 'Products'),
  NavDest('/invoices', Icons.receipt_long_outlined, Icons.receipt_long, 'Invoices'),
  NavDest('/quotes', Icons.request_quote_outlined, Icons.request_quote, 'Quotes'),
  NavDest('/expenses', Icons.payments_outlined, Icons.payments, 'Expenses'),
  NavDest('/certificates', Icons.workspace_premium_outlined,
      Icons.workspace_premium, 'Certificates'),
  NavDest('/banners', Icons.campaign_outlined, Icons.campaign, 'Agent Banners'),
];

const maxBarItems = 4;
const defaultBar = ['/', '/tickets', '/assets', '/credentials'];

NavDest? navDestFor(String path) {
  for (final d in navCatalog) {
    if (d.path == path) return d;
  }
  return null;
}

class UiPrefs {
  /// Paths on the bottom bar, in order (More is always added last).
  final List<String> bar;

  /// Every other path, in the order the More screen lists them.
  final List<String> more;
  final bool tourDone;
  final Set<String> tipsSeen;

  const UiPrefs({
    this.bar = defaultBar,
    this.more = const [],
    this.tourDone = false,
    this.tipsSeen = const {},
  });

  List<NavDest> get barDests =>
      [for (final p in bar) if (navDestFor(p) != null) navDestFor(p)!];

  /// Everything not on the bar: the saved order first, then anything new.
  List<NavDest> get moreDests {
    final out = <NavDest>[];
    final seen = {...bar};
    for (final p in more) {
      final d = navDestFor(p);
      if (d != null && seen.add(p)) out.add(d);
    }
    for (final d in navCatalog) {
      if (seen.add(d.path)) out.add(d);
    }
    return out;
  }

  UiPrefs copyWith({
    List<String>? bar,
    List<String>? more,
    bool? tourDone,
    Set<String>? tipsSeen,
  }) =>
      UiPrefs(
        bar: bar ?? this.bar,
        more: more ?? this.more,
        tourDone: tourDone ?? this.tourDone,
        tipsSeen: tipsSeen ?? this.tipsSeen,
      );
}

class UiPrefsNotifier extends AsyncNotifier<UiPrefs> {
  static const _kBar = 'ui.nav.bar';
  static const _kMore = 'ui.nav.more';
  static const _kTour = 'ui.tourDone';
  static const _kTips = 'ui.tipsSeen';

  @override
  Future<UiPrefs> build() async {
    final p = await SharedPreferences.getInstance();
    final bar = (p.getStringList(_kBar) ?? defaultBar)
        .where((x) => navDestFor(x) != null)
        .take(maxBarItems)
        .toList();
    return UiPrefs(
      bar: bar,
      more: p.getStringList(_kMore) ?? const [],
      tourDone: p.getBool(_kTour) ?? false,
      tipsSeen: (p.getStringList(_kTips) ?? const []).toSet(),
    );
  }

  UiPrefs get _cur => state.value ?? const UiPrefs();

  Future<void> setNav(List<String> bar, List<String> more) async {
    final b = bar.take(maxBarItems).toList();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kBar, b);
    await p.setStringList(_kMore, more);
    state = AsyncValue.data(_cur.copyWith(bar: b, more: more));
  }

  Future<void> resetNav() => setNav(defaultBar, const []);

  Future<void> setTourDone(bool done) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kTour, done);
    state = AsyncValue.data(_cur.copyWith(tourDone: done));
  }

  Future<void> markTipSeen(String id) async {
    final tips = {..._cur.tipsSeen, id};
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kTips, tips.toList());
    state = AsyncValue.data(_cur.copyWith(tipsSeen: tips));
  }

  Future<void> resetTips() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTips);
    state = AsyncValue.data(_cur.copyWith(tipsSeen: const {}));
  }
}

final uiPrefsProvider =
    AsyncNotifierProvider<UiPrefsNotifier, UiPrefs>(UiPrefsNotifier.new);

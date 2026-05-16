import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const _items = [
    _MoreItem('/timer', Icons.timer_outlined, 'Labour Timer'),
    _MoreItem('/trips', Icons.route_outlined, 'Trips'),
    _MoreItem('/clients', Icons.business_outlined, 'Clients'),
    _MoreItem('/contacts', Icons.contacts_outlined, 'Contacts'),
    _MoreItem('/documents', Icons.description_outlined, 'Documents'),
    _MoreItem('/domains', Icons.dns_outlined, 'Domains'),
    _MoreItem('/locations', Icons.location_on_outlined, 'Locations'),
    _MoreItem('/networks', Icons.lan_outlined, 'Networks'),
    _MoreItem('/software', Icons.apps_outlined, 'Software'),
    _MoreItem('/vendors', Icons.store_outlined, 'Vendors'),
    _MoreItem('/products', Icons.shopping_bag_outlined, 'Products'),
    _MoreItem('/invoices', Icons.receipt_long_outlined, 'Invoices'),
    _MoreItem('/quotes', Icons.request_quote_outlined, 'Quotes'),
    _MoreItem('/expenses', Icons.payments_outlined, 'Expenses'),
    _MoreItem('/certificates', Icons.workspace_premium_outlined, 'Certificates'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView.separated(
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i == _items.length) {
            return ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings'),
            );
          }
          final item = _items[i];
          return ListTile(
            leading: Icon(item.icon),
            title: Text(item.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(item.path),
          );
        },
      ),
    );
  }
}

class _MoreItem {
  final String path;
  final IconData icon;
  final String label;
  const _MoreItem(this.path, this.icon, this.label);
}

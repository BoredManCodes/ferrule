import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/util.dart';
import '../../core/widgets.dart';
import '../contacts/contact_model.dart';
import '../contacts/contact_repository.dart';
import '../tickets/ticket_repository.dart';
import 'client_model.dart';
import 'client_repository.dart';

class ClientDetailScreen extends ConsumerWidget {
  final int id;
  const ClientDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clientProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.value?.name ?? 'Client'),
        actions: [
          if (async.value != null && !async.value!.archived)
            IconButton(
              tooltip: 'Archive',
              icon: const Icon(Icons.archive_outlined),
              onPressed: () => _archive(context, ref),
            ),
          if (async.value != null && async.value!.archived)
            IconButton(
              tooltip: 'Unarchive',
              icon: const Icon(Icons.unarchive_outlined),
              onPressed: () => _unarchive(context, ref),
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(clientProvider(id));
              ref.invalidate(clientLocationsProvider(id));
              ref.invalidate(contactsProvider);
              ref.invalidate(ticketsProvider);
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(clientProvider(id))),
        data: (c) {
          if (c == null) {
            return const EmptyView(icon: Icons.search_off, title: 'Not found');
          }
          return _ClientBody(client: c);
        },
      ),
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final name = ref.read(clientProvider(id)).value?.name ?? 'this client';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive client?'),
        content: Text(
            'Archive "$name"? They\'ll be hidden from default lists but data is preserved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref.read(clientRepositoryProvider).archive(id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Archived' : 'Archive failed')));
      if (ok) {
        ref.invalidate(clientsProvider);
        ref.invalidate(clientProvider(id));
      }
    }
  }

  Future<void> _unarchive(BuildContext context, WidgetRef ref) async {
    final name = ref.read(clientProvider(id)).value?.name ?? 'this client';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unarchive client?'),
        content: Text('Restore "$name" to the default client list?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unarchive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref.read(clientRepositoryProvider).unarchive(id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Unarchived' : 'Unarchive failed')));
      if (ok) {
        ref.invalidate(clientsProvider);
        ref.invalidate(clientProvider(id));
      }
    }
  }
}

class _ClientBody extends ConsumerWidget {
  final Client client;
  const _ClientBody({required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(clientLocationsProvider(client.id));
    final contactsAsync = ref.watch(contactsProvider);
    final ticketsAsync = ref.watch(ticketsProvider);

    final contacts = contactsAsync.value
            ?.where((c) => c.clientId == client.id)
            .toList() ??
        const <Contact>[];
    final primaryContact = contacts.firstWhereOrNull((c) => c.primary);
    final primaryLocation = locationsAsync.value
        ?.firstWhereOrNull((r) => toBool(r['location_primary']));

    final tickets = ticketsAsync.value
        ?.where((t) => t.clientId == client.id)
        .toList();
    final openTickets = tickets?.where((t) => !t.isResolved).length;
    final closedTickets = tickets?.where((t) => t.isResolved).length;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(clientProvider(client.id));
        ref.invalidate(clientLocationsProvider(client.id));
        ref.invalidate(contactsProvider);
        ref.invalidate(ticketsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _Header(client: client),
          if (primaryLocation != null) ...[
            const SectionHeader('Primary Location'),
            _LocationCard(row: primaryLocation),
          ],
          if (primaryContact != null) ...[
            const SectionHeader('Primary Contact'),
            _ContactCard(contact: primaryContact),
          ],
          _BillingSection(client: client),
          _SupportSection(
            open: openTickets,
            closed: closedTickets,
            loading: ticketsAsync.isLoading,
          ),
          if (contacts.length > 1 ||
              (contacts.isNotEmpty && primaryContact == null)) ...[
            const SectionHeader('Contacts'),
            _ContactsList(contacts: contacts),
          ],
          if (client.notes != null) ...[
            const SectionHeader('Notes'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(client.notes!),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Client client;
  const _Header({required this.client});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.business_outlined,
                size: 28, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(client.name ?? '(unnamed)',
                    style: Theme.of(context).textTheme.headlineSmall),
                if (client.type != null) ...[
                  const SizedBox(height: 4),
                  Text(client.type!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                if (client.website != null) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _openWebsite(client.website!),
                    child: Text(
                      client.website!,
                      style: TextStyle(
                          color: scheme.primary,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (client.favorite)
            const Icon(Icons.star, color: Colors.amber, size: 24),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _LocationCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final address = _composeAddress(row);
    final phone = _composePhone(row['location_phone_country_code'],
        row['location_phone'], row['location_phone_extension']);
    final children = <Widget>[
      if (address != null)
        KeyValueTile(
          label: 'Address',
          value: address,
          icon: Icons.place_outlined,
          onTap: () => launchUrl(Uri.parse(
              'https://maps.google.com/?q=${Uri.encodeQueryComponent(address.replaceAll('\n', ', '))}')),
          trailing: const Icon(Icons.open_in_new, size: 18),
        ),
      if (phone.isNotEmpty)
        KeyValueTile(
          label: 'Phone',
          value: phone,
          icon: Icons.phone_outlined,
          onTap: () =>
              launchUrl(Uri.parse('tel:${str(row['location_phone'])}')),
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: children),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Contact contact;
  const _ContactCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      KeyValueTile(
        label: 'Name',
        value: contact.name ?? '(unnamed)',
        icon: Icons.person_outline,
        onTap: () => _gotoContact(context, contact.id),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
      if (contact.email != null)
        KeyValueTile(
          label: 'Email',
          value: contact.email!,
          icon: Icons.mail_outline,
          onTap: () => launchUrl(Uri.parse('mailto:${contact.email}')),
        ),
      if (contact.phone != null)
        KeyValueTile(
          label: 'Phone',
          value: contact.phone!,
          icon: Icons.phone_outlined,
          onTap: () => launchUrl(Uri.parse('tel:${contact.phone}')),
        ),
      if (contact.mobile != null)
        KeyValueTile(
          label: 'Mobile',
          value: contact.mobile!,
          icon: Icons.smartphone,
          onTap: () => launchUrl(Uri.parse('tel:${contact.mobile}')),
        ),
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: children),
    );
  }
}

class _BillingSection extends StatelessWidget {
  final Client client;
  const _BillingSection({required this.client});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (client.rate != null && client.rate! > 0) {
      final money = NumberFormat.currency(
        name: client.currencyCode ?? '',
        symbol: client.currencyCode == null ? null : '',
      );
      final formatted = client.currencyCode == null
          ? money.format(client.rate)
          : '${money.format(client.rate)} ${client.currencyCode}';
      rows.add(KeyValueTile(
          label: 'Hourly Rate',
          value: formatted,
          icon: Icons.payments_outlined));
    }
    if (client.netTerms != null) {
      rows.add(KeyValueTile(
          label: 'Net Terms',
          value: '${client.netTerms} days',
          icon: Icons.calendar_today_outlined));
    }
    if (client.currencyCode != null) {
      rows.add(KeyValueTile(
          label: 'Currency',
          value: client.currencyCode!,
          icon: Icons.money_outlined));
    }
    if (client.taxIdNumber != null) {
      rows.add(KeyValueTile(
          label: 'Tax ID',
          value: client.taxIdNumber!,
          icon: Icons.receipt_long_outlined));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Billing'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class _SupportSection extends StatelessWidget {
  final int? open;
  final int? closed;
  final bool loading;
  const _SupportSection(
      {required this.open, required this.closed, required this.loading});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Support'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Open',
                    value: loading
                        ? '…'
                        : (open?.toString() ?? '—'),
                    color: scheme.primary,
                    icon: Icons.support_agent,
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    label: 'Closed',
                    value: loading
                        ? '…'
                        : (closed?.toString() ?? '—'),
                    color: scheme.onSurfaceVariant,
                    icon: Icons.check_circle_outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                )),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
      ],
    );
  }
}

class _ContactsList extends StatelessWidget {
  final List<Contact> contacts;
  const _ContactsList({required this.contacts});

  @override
  Widget build(BuildContext context) {
    final sorted = [...contacts]..sort((a, b) {
        if (a.primary != b.primary) return a.primary ? -1 : 1;
        return (a.name ?? '').compareTo(b.name ?? '');
      });
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: sorted[i].primary
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: Text(
                  _initials(sorted[i].name),
                  style: TextStyle(
                    color: sorted[i].primary
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : null,
                  ),
                ),
              ),
              title: Text(sorted[i].name ?? '(unnamed)'),
              subtitle: Text([
                if (sorted[i].title != null) sorted[i].title!,
                if (sorted[i].primary) 'Primary',
              ].join(' • ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _gotoContact(context, sorted[i].id),
            ),
          ],
        ],
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

void _gotoContact(BuildContext context, int contactId) {
  context.push('/contacts/$contactId');
}

Future<void> _openWebsite(String s) async {
  var u = s.trim();
  if (!u.contains('://')) u = 'https://$u';
  final uri = Uri.tryParse(u);
  if (uri != null) await launchUrl(uri);
}

String? _composeAddress(Map<String, dynamic> r) {
  final parts = <String>[
    if (str(r['location_address']) != null) str(r['location_address'])!,
    [
      str(r['location_city']),
      str(r['location_state']),
      str(r['location_zip']),
    ].whereType<String>().join(', '),
    if (str(r['location_country']) != null) str(r['location_country'])!,
  ].where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  return parts.join('\n');
}

String _composePhone(dynamic countryCode, dynamic number, [dynamic ext]) {
  final cc = str(countryCode);
  final n = str(number);
  if (n == null) return '';
  var out = cc != null ? '+$cc $n' : n;
  final e = str(ext);
  if (e != null) out = '$out ext. $e';
  return out;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

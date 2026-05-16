import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets.dart';
import '../assets/asset_model.dart';
import '../assets/asset_repository.dart';
import '../clients/client_repository.dart';
import '../credentials/credential_model.dart';
import '../credentials/credential_repository.dart';
import '../tickets/ticket_model.dart';
import '../tickets/ticket_repository.dart';
import 'contact_model.dart';
import 'contact_repository.dart';

class ContactDetailScreen extends ConsumerWidget {
  final int id;
  const ContactDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contactProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.value?.name ?? 'Contact'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(contactProvider(id));
              ref.invalidate(assetsProvider);
              ref.invalidate(credentialsListProvider);
              ref.invalidate(ticketsProvider);
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(contactProvider(id))),
        data: (c) {
          if (c == null) {
            return const EmptyView(
                icon: Icons.search_off, title: 'Not found');
          }
          return _Body(contact: c);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final Contact contact;
  const _Body({required this.contact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = contact.clientId == null || contact.clientId == 0
        ? const AsyncValue.data(null)
        : ref.watch(clientProvider(contact.clientId!));
    final assetsAsync = ref.watch(assetsProvider);
    final credentialsAsync = ref.watch(credentialsListProvider);
    final ticketsAsync = ref.watch(ticketsProvider);

    final assets = assetsAsync.value
            ?.where((a) => a.contactId == contact.id)
            .toList() ??
        const <Asset>[];
    final credentials = credentialsAsync.value?.items
            .where((c) => c.contactId == contact.id)
            .toList() ??
        const <Credential>[];
    final tickets = ticketsAsync.value
            ?.where((t) => t.contactId == contact.id)
            .toList()
        ?..sort((a, b) {
          final av = a.createdAt ?? DateTime(0);
          final bv = b.createdAt ?? DateTime(0);
          return bv.compareTo(av);
        });

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(contactProvider(contact.id));
        if (contact.clientId != null && contact.clientId != 0) {
          ref.invalidate(clientProvider(contact.clientId!));
        }
        ref.invalidate(assetsProvider);
        ref.invalidate(credentialsListProvider);
        ref.invalidate(ticketsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _Header(contact: contact),
          if (clientAsync.value != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                onTap: () => context.push('/clients/${contact.clientId}'),
                child: Row(
                  children: [
                    Icon(Icons.business_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        clientAsync.value!.name ?? 'Client',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_flagChips(context).isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _flagChips(context),
              ),
            ),
          ],
          const SectionHeader('Contact'),
          _ContactCard(contact: contact),
          if (contact.createdAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.history,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Added ${DateFormat.yMMMd().format(contact.createdAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (contact.notes != null) ...[
            const SectionHeader('Notes'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(contact.notes!),
                ),
              ),
            ),
          ],
          _RelatedAssets(assets: assets, loading: assetsAsync.isLoading),
          _RelatedCredentials(
              credentials: credentials,
              loading: credentialsAsync.isLoading),
          _RelatedTickets(
              tickets: tickets ?? const <Ticket>[],
              loading: ticketsAsync.isLoading),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<Widget> _flagChips(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Chip mk(String label, Color color, IconData icon) => Chip(
          avatar: Icon(icon, size: 14, color: color),
          label: Text(label, style: TextStyle(fontSize: 11, color: color)),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          backgroundColor: color.withValues(alpha: 0.08),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
    return [
      if (contact.primary) mk('Primary', scheme.primary, Icons.star),
      if (contact.important)
        mk('Important', Colors.orange, Icons.priority_high),
      if (contact.technical)
        mk('Technical', Colors.blue, Icons.build_outlined),
      if (contact.billing)
        mk('Billing', Colors.green, Icons.attach_money_outlined),
    ];
  }
}

class _Header extends StatelessWidget {
  final Contact contact;
  const _Header({required this.contact});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              _initials(contact.name),
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name ?? '(unnamed)',
                    style: Theme.of(context).textTheme.headlineSmall),
                if (contact.title != null) ...[
                  const SizedBox(height: 4),
                  Text(contact.title!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                if (contact.department != null) ...[
                  const SizedBox(height: 2),
                  Text(contact.department!,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
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

class _ContactCard extends StatelessWidget {
  final Contact contact;
  const _ContactCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (contact.email != null) {
      rows.add(KeyValueTile(
        label: 'Email',
        value: contact.email!,
        icon: Icons.mail_outline,
        onTap: () => launchUrl(Uri.parse('mailto:${contact.email}')),
      ));
    }
    if (contact.phone != null) {
      rows.add(KeyValueTile(
        label: 'Phone',
        value: contact.phone!,
        icon: Icons.phone_outlined,
        onTap: () => launchUrl(Uri.parse('tel:${contact.phone}')),
      ));
    }
    if (contact.mobile != null) {
      rows.add(KeyValueTile(
        label: 'Mobile',
        value: contact.mobile!,
        icon: Icons.smartphone,
        onTap: () => launchUrl(Uri.parse('tel:${contact.mobile}')),
      ));
    }
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('No contact details on file.'),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: rows),
    );
  }
}

class _RelatedAssets extends StatelessWidget {
  final List<Asset> assets;
  final bool loading;
  const _RelatedAssets({required this.assets, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (!loading && assets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Related Assets${assets.isNotEmpty ? ' (${assets.length})' : ''}',
        ),
        if (loading && assets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(),
          )
        else
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (var i = 0; i < assets.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(assets[i].icon),
                    title: Text(assets[i].name ?? '(unnamed)'),
                    subtitle: Text([
                      assets[i].type,
                      [assets[i].make, assets[i].model]
                          .whereType<String>()
                          .join(' '),
                      assets[i].status,
                    ]
                        .map((s) => s?.toString().trim() ?? '')
                        .where((s) => s.isNotEmpty)
                        .join(' • ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/assets/${assets[i].id}'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RelatedCredentials extends StatelessWidget {
  final List<Credential> credentials;
  final bool loading;
  const _RelatedCredentials(
      {required this.credentials, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (!loading && credentials.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Credentials${credentials.isNotEmpty ? ' (${credentials.length})' : ''}',
        ),
        if (loading && credentials.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(),
          )
        else
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (var i = 0; i < credentials.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.vpn_key_outlined),
                    title: Text(credentials[i].name ?? '(unnamed)'),
                    subtitle: Text([
                      credentials[i].username,
                      credentials[i].description,
                    ]
                        .map((s) => s?.toString().trim() ?? '')
                        .where((s) => s.isNotEmpty)
                        .join(' • ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.push('/credentials/${credentials[i].id}'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RelatedTickets extends StatelessWidget {
  final List<Ticket> tickets;
  final bool loading;
  const _RelatedTickets({required this.tickets, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (!loading && tickets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Related Tickets${tickets.isNotEmpty ? ' (${tickets.length})' : ''}',
        ),
        if (loading && tickets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(),
          )
        else
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (var i = 0; i < tickets.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: tickets[i].isResolved
                          ? Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh
                          : Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor: tickets[i].isResolved
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onPrimaryContainer,
                      child: Icon(
                        tickets[i].isResolved
                            ? Icons.check_circle_outline
                            : Icons.support_agent,
                        size: 18,
                      ),
                    ),
                    title: Text(tickets[i].subject ?? '(no subject)'),
                    subtitle: Text([
                      tickets[i].displayNumber,
                      tickets[i].priority,
                      tickets[i].isResolved ? 'Closed' : 'Open',
                      tickets[i].createdAt == null
                          ? null
                          : DateFormat.yMMMd().format(tickets[i].createdAt!),
                    ]
                        .map((s) => s?.toString().trim() ?? '')
                        .where((s) => s.isNotEmpty)
                        .join(' • ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/tickets/${tickets[i].id}'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

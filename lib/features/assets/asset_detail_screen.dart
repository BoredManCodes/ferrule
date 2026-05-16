import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets.dart';
import '../clients/client_repository.dart';
import '../contacts/contact_repository.dart';
import '../credentials/credential_model.dart';
import '../credentials/credential_repository.dart';
import 'asset_repository.dart';

class AssetDetailScreen extends ConsumerWidget {
  final int id;
  const AssetDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(assetProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.value?.name ?? 'Asset'),
        actions: [
          if (async.value != null) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/assets/$id/edit'),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(assetProvider(id)),
        ),
        data: (asset) {
          if (asset == null) {
            return const EmptyView(
                icon: Icons.search_off, title: 'Asset not found');
          }
          final df = DateFormat.yMMMd();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(asset.icon,
                          size: 28,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(asset.name ?? '(unnamed)',
                              style:
                                  Theme.of(context).textTheme.headlineSmall),
                          if (asset.type != null)
                            Text(asset.type!,
                                style:
                                    Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (asset.description != null) ...[
                const SectionHeader('Description'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(asset.description!),
                ),
              ],
              const SectionHeader('Hardware'),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    if (asset.make != null)
                      KeyValueTile(
                          label: 'Make',
                          value: asset.make!,
                          icon: Icons.business),
                    if (asset.model != null)
                      KeyValueTile(
                          label: 'Model',
                          value: asset.model!,
                          icon: Icons.memory),
                    if (asset.serial != null)
                      KeyValueTile(
                          label: 'Serial',
                          value: asset.serial!,
                          icon: Icons.qr_code),
                    if (asset.os != null)
                      KeyValueTile(
                          label: 'OS',
                          value: asset.os!,
                          icon: Icons.computer),
                    if (asset.status != null)
                      KeyValueTile(
                          label: 'Status',
                          value: asset.status!,
                          icon: Icons.info_outline),
                  ],
                ),
              ),
              if (asset.ip != null || asset.mac != null || asset.uri != null) ...[
                const SectionHeader('Network'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (asset.ip != null)
                        KeyValueTile(
                            label: 'IP',
                            value: asset.ip!,
                            icon: Icons.lan_outlined),
                      if (asset.mac != null)
                        KeyValueTile(
                            label: 'MAC',
                            value: asset.mac!,
                            icon: Icons.settings_ethernet),
                      if (asset.uri != null)
                        KeyValueTile(
                          label: 'URI',
                          value: asset.uri!,
                          icon: Icons.link,
                          onTap: () => _open(asset.uri!),
                          trailing: const Icon(Icons.open_in_new, size: 18),
                        ),
                    ],
                  ),
                ),
              ],
              if (asset.purchaseDate != null ||
                  asset.warrantyExpire != null ||
                  asset.installDate != null) ...[
                const SectionHeader('Dates'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (asset.purchaseDate != null)
                        KeyValueTile(
                            label: 'Purchased',
                            value: df.format(asset.purchaseDate!),
                            icon: Icons.shopping_cart_outlined),
                      if (asset.installDate != null)
                        KeyValueTile(
                            label: 'Installed',
                            value: df.format(asset.installDate!),
                            icon: Icons.build_outlined),
                      if (asset.warrantyExpire != null)
                        KeyValueTile(
                            label: 'Warranty Expires',
                            value: df.format(asset.warrantyExpire!),
                            icon: Icons.verified_outlined),
                    ],
                  ),
                ),
              ],
              _AssignmentSection(
                clientId: asset.clientId,
                contactId: asset.contactId,
              ),
              _RelatedCredentialsSection(assetId: asset.id),
              if (asset.notes != null) ...[
                const SectionHeader('Notes'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(asset.notes!),
                ),
              ],
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(String uri) async {
    final u = Uri.tryParse(uri);
    if (u != null) await launchUrl(u);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete asset?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await ref.read(assetRepositoryProvider).delete(id);
    if (!context.mounted) return;
    if (r.ok) {
      ref.invalidate(assetsProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Asset deleted')));
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.error ?? 'Failed to delete')));
    }
  }
}

class _AssignmentSection extends ConsumerWidget {
  final int? clientId;
  final int? contactId;
  const _AssignmentSection({required this.clientId, required this.contactId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasClient = clientId != null && clientId != 0;
    final hasContact = contactId != null && contactId != 0;
    if (!hasClient && !hasContact) return const SizedBox.shrink();

    final clientAsync =
        hasClient ? ref.watch(clientProvider(clientId!)) : null;
    final contactAsync =
        hasContact ? ref.watch(contactProvider(contactId!)) : null;
    final contact = contactAsync?.value;

    final rows = <Widget>[];
    if (hasClient) {
      rows.add(KeyValueTile(
        label: 'Client',
        value: clientAsync?.value?.name ?? '#$clientId',
        icon: Icons.business_outlined,
        onTap: () => context.push('/clients/$clientId'),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ));
    }
    if (hasContact) {
      rows.add(KeyValueTile(
        label: 'Contact',
        value: contact?.name ?? '#$contactId',
        icon: Icons.person_outline,
        onTap: () => context.push('/contacts/$contactId'),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ));
      if (contact?.email != null) {
        rows.add(KeyValueTile(
          label: 'Email',
          value: contact!.email!,
          icon: Icons.mail_outline,
          onTap: () => launchUrl(Uri.parse('mailto:${contact.email}')),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Assignment'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class _RelatedCredentialsSection extends ConsumerWidget {
  final int assetId;
  const _RelatedCredentialsSection({required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(credentialsListProvider);
    final loading = async.isLoading;
    final List<Credential> creds = async.value?.items
            .where((c) => c.assetId == assetId)
            .toList() ??
        const <Credential>[];
    if (!loading && creds.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
            'Credentials${creds.isNotEmpty ? ' (${creds.length})' : ''}'),
        if (loading && creds.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(),
          )
        else
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (var i = 0; i < creds.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.vpn_key_outlined),
                    title: Text(creds[i].name ?? '(unnamed)'),
                    subtitle: Text([
                      creds[i].username,
                      creds[i].description,
                    ]
                        .map((s) => s?.toString().trim() ?? '')
                        .where((s) => s.isNotEmpty)
                        .join(' • ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/credentials/${creds[i].id}'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

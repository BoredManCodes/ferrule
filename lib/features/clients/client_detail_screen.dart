import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets.dart';
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
              onPressed: () async {
                final ok =
                    await ref.read(clientRepositoryProvider).archive(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok ? 'Archived' : 'Archive failed')));
                  if (ok) {
                    ref.invalidate(clientsProvider);
                    ref.invalidate(clientProvider(id));
                  }
                }
              },
            ),
          if (async.value != null && async.value!.archived)
            IconButton(
              tooltip: 'Unarchive',
              icon: const Icon(Icons.unarchive_outlined),
              onPressed: () async {
                final ok =
                    await ref.read(clientRepositoryProvider).unarchive(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text(ok ? 'Unarchived' : 'Unarchive failed')));
                  if (ok) {
                    ref.invalidate(clientsProvider);
                    ref.invalidate(clientProvider(id));
                  }
                }
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name ?? '(unnamed)',
                          style: Theme.of(context).textTheme.headlineSmall),
                      if (c.type != null) ...[
                        const SizedBox(height: 4),
                        Text(c.type!),
                      ],
                    ],
                  ),
                ),
              ),
              const SectionHeader('Contact'),
              Card(
                child: Column(
                  children: [
                    if (c.email != null)
                      KeyValueTile(
                        label: 'Email',
                        value: c.email!,
                        icon: Icons.mail_outline,
                        onTap: () => launchUrl(Uri.parse('mailto:${c.email}')),
                      ),
                    if (c.phone != null)
                      KeyValueTile(
                        label: 'Phone',
                        value: c.phone!,
                        icon: Icons.phone_outlined,
                        onTap: () => launchUrl(Uri.parse('tel:${c.phone}')),
                      ),
                    if (c.website != null)
                      KeyValueTile(
                        label: 'Website',
                        value: c.website!,
                        icon: Icons.public,
                        onTap: () {
                          var s = c.website!;
                          if (!s.startsWith('http')) s = 'https://$s';
                          launchUrl(Uri.parse(s));
                        },
                      ),
                  ],
                ),
              ),
              if (c.notes != null) ...[
                const SectionHeader('Notes'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(c.notes!),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

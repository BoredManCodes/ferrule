import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets.dart';
import 'contact_repository.dart';

class ContactDetailScreen extends ConsumerWidget {
  final int id;
  const ContactDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contactProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(async.value?.name ?? 'Contact')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(contactProvider(id))),
        data: (c) {
          if (c == null) {
            return const EmptyView(
                icon: Icons.search_off, title: 'Not found');
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
                      if (c.title != null) ...[
                        const SizedBox(height: 4),
                        Text(c.title!),
                      ],
                      if (c.department != null) ...[
                        const SizedBox(height: 4),
                        Text(c.department!,
                            style:
                                Theme.of(context).textTheme.bodySmall),
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
                        onTap: () =>
                            launchUrl(Uri.parse('mailto:${c.email}')),
                      ),
                    if (c.phone != null)
                      KeyValueTile(
                        label: 'Phone',
                        value: c.phone!,
                        icon: Icons.phone_outlined,
                        onTap: () => launchUrl(Uri.parse('tel:${c.phone}')),
                      ),
                    if (c.mobile != null)
                      KeyValueTile(
                        label: 'Mobile',
                        value: c.mobile!,
                        icon: Icons.smartphone,
                        onTap: () => launchUrl(Uri.parse('tel:${c.mobile}')),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

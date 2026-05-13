import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets.dart';
import 'contact_repository.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contactsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search contacts…',
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.invalidate(contactsProvider)),
              data: (list) {
                final filtered = list.where((c) {
                  if (c.archived) return false;
                  if (_search.isEmpty) return true;
                  final hay =
                      '${c.name ?? ''} ${c.email ?? ''} ${c.title ?? ''}'
                          .toLowerCase();
                  return hay.contains(_search);
                }).toList();
                if (filtered.isEmpty) {
                  return const EmptyView(
                      icon: Icons.contacts_outlined, title: 'No contacts');
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    return ListTile(
                      onTap: () => context.push('/contacts/${c.id}'),
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        child: Text(
                          (c.name ?? '?').characters.first.toUpperCase(),
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer),
                        ),
                      ),
                      title: Text(c.name ?? '(unnamed)'),
                      subtitle: Text([
                        if (c.title != null) c.title!,
                        if (c.email != null) c.email!,
                      ].join(' • ')),
                      trailing: c.primary
                          ? const Icon(Icons.star, size: 18)
                          : const Icon(Icons.chevron_right),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

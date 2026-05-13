import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets.dart';
import 'client_repository.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  String _search = '';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(clientsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clients'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(clientsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search clients…',
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Show archived'),
                  selected: _showArchived,
                  onSelected: (v) => setState(() => _showArchived = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(clientsProvider),
              ),
              data: (clients) {
                final filtered = clients.where((c) {
                  if (!_showArchived && c.archived) return false;
                  if (_search.isEmpty) return true;
                  final hay =
                      '${c.name ?? ''} ${c.type ?? ''} ${c.email ?? ''}'
                          .toLowerCase();
                  return hay.contains(_search);
                }).toList();
                if (filtered.isEmpty) {
                  return const EmptyView(
                      icon: Icons.business_outlined, title: 'No clients');
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(clientsProvider),
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      return ListTile(
                        onTap: () => context.push('/clients/${c.id}'),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .tertiaryContainer,
                          child: Text(
                            (c.name ?? '?').characters.first.toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onTertiaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        title: Text(c.name ?? '(unnamed)'),
                        subtitle: Text([
                          if (c.type != null) c.type!,
                          if (c.email != null) c.email!,
                        ].join(' • ')),
                        trailing: c.archived
                            ? const Chip(
                                label: Text('Archived',
                                    style: TextStyle(fontSize: 11)),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              )
                            : const Icon(Icons.chevron_right),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

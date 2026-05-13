import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets.dart';
import 'asset_model.dart';
import 'asset_repository.dart';

class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  String _search = '';
  String? _typeFilter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(assetsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assets'),
        actions: [
          IconButton(
            tooltip: 'Scan QR',
            onPressed: () => context.push('/assets/scan'),
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(assetsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'scan',
            onPressed: () => context.push('/assets/scan'),
            tooltip: 'Scan QR',
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'new',
            onPressed: () => context.push('/assets/new'),
            icon: const Icon(Icons.add),
            label: const Text('New Asset'),
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
                hintText: 'Search assets…',
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              scrollDirection: Axis.horizontal,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _typeFilter == null,
                  onSelected: (_) => setState(() => _typeFilter = null),
                ),
                const SizedBox(width: 8),
                for (final t in Asset.types) ...[
                  FilterChip(
                    label: Text(t),
                    selected: _typeFilter == t,
                    onSelected: (_) =>
                        setState(() => _typeFilter = _typeFilter == t ? null : t),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () {
                final n = ref.watch(assetLoadProgressProvider);
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        n > 0 ? 'Loaded $n assets…' : 'Loading assets…',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(assetsProvider),
              ),
              data: (assets) {
                final filtered = assets.where((a) {
                  if (_typeFilter != null && a.type != _typeFilter) return false;
                  if (_search.isEmpty) return true;
                  final hay =
                      '${a.name ?? ''} ${a.make ?? ''} ${a.model ?? ''} ${a.serial ?? ''} ${a.ip ?? ''}'
                          .toLowerCase();
                  return hay.contains(_search);
                }).toList();
                if (filtered.isEmpty) {
                  return const EmptyView(
                    icon: Icons.devices_other_outlined,
                    title: 'No assets',
                    message: 'Tap + to add one.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(assetsProvider),
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = filtered[i];
                      return ListTile(
                        onTap: () => context.push('/assets/${a.id}'),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          child: Icon(a.icon,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer),
                        ),
                        title: Text(a.name ?? '(unnamed)'),
                        subtitle: Text([
                          if (a.type != null) a.type!,
                          if (a.ip != null) a.ip!,
                          if (a.status != null) a.status!,
                        ].join(' • ')),
                        trailing: const Icon(Icons.chevron_right),
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

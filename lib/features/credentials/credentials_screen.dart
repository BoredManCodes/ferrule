import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/providers.dart';
import '../../core/widgets.dart';
import 'credential_repository.dart';

class CredentialsScreen extends ConsumerStatefulWidget {
  const CredentialsScreen({super.key});

  @override
  ConsumerState<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends ConsumerState<CredentialsScreen> {
  String _search = '';
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final creds = ref.watch(credentialsProvider).value;
    final decryptSet = (creds?.decryptPassword ?? '').isNotEmpty;
    final async = ref.watch(credentialsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(credentialsListProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: decryptSet
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/credentials/new'),
              icon: const Icon(Icons.add),
              label: const Text('New'),
            )
          : null,
      body: !decryptSet
          ? _DecryptPasswordPrompt()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search credentials…',
                    ),
                    onChanged: (v) =>
                        setState(() => _search = v.toLowerCase()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('Favorites'),
                        avatar: const Icon(Icons.star_outline, size: 16),
                        selected: _favoritesOnly,
                        onSelected: (v) =>
                            setState(() => _favoritesOnly = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: async.when(
                    loading: () {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Decrypting first page…'),
                          ],
                        ),
                      );
                    },
                    error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () =>
                          ref.invalidate(credentialsListProvider),
                    ),
                    data: (s) {
                      final filtered = s.items.where((c) {
                        if (_favoritesOnly && !c.favorite) return false;
                        if (_search.isEmpty) return true;
                        final hay =
                            '${c.name ?? ''} ${c.username ?? ''} ${c.uri ?? ''} ${c.description ?? ''}'
                                .toLowerCase();
                        return hay.contains(_search);
                      }).toList();

                      if (filtered.isEmpty && s.allLoaded) {
                        return const EmptyView(
                          icon: Icons.vpn_key_outlined,
                          title: 'No credentials',
                          message: 'Tap + to add one.',
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(credentialsListProvider),
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.pixels >=
                                    n.metrics.maxScrollExtent - 200 &&
                                !s.loadingMore &&
                                !s.allLoaded) {
                              ref
                                  .read(credentialsListProvider.notifier)
                                  .retryMore();
                            }
                            return false;
                          },
                          child: ListView.separated(
                            itemCount: filtered.length + 1,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              if (i == filtered.length) {
                                return _LoadMoreFooter(state: s);
                              }
                              final c = filtered[i];
                              return ListTile(
                                onTap: () =>
                                    context.push('/credentials/${c.id}'),
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer,
                                  child: Icon(
                                    Icons.vpn_key,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                                    size: 20,
                                  ),
                                ),
                                title: Text(c.name ?? '(unnamed)'),
                                subtitle: Text([
                                  if (c.username != null) c.username!,
                                  if (c.uri != null) c.uri!,
                                ].join(' • ')),
                                trailing: c.favorite
                                    ? const Icon(Icons.star, size: 18)
                                    : const Icon(Icons.chevron_right),
                              );
                            },
                          ),
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

class _LoadMoreFooter extends ConsumerWidget {
  final CredentialsListState state;
  const _LoadMoreFooter({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (state.allLoaded) {
      if (state.items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '${state.items.length} credentials',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
      );
    }
    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 24),
            const SizedBox(height: 6),
            Text(
              state.loadMoreError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () =>
                  ref.read(credentialsListProvider.notifier).retryMore(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 8),
            Text(
              'Loaded ${state.items.length}…',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecryptPasswordPrompt extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DecryptPasswordPrompt> createState() =>
      _DecryptPasswordPromptState();
}

class _DecryptPasswordPromptState
    extends ConsumerState<_DecryptPasswordPrompt> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Unlock Vault',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the API decrypt password to view stored credentials. This is the password configured on your API key.',
                    textAlign: TextAlign.center,
                    style:
                        Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Decrypt Password',
                      prefixIcon: const Icon(Icons.key),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      final pw = _controller.text.trim();
                      if (pw.isEmpty) return;
                      await ref
                          .read(credentialsProvider.notifier)
                          .setDecryptPassword(pw);
                      ref.invalidate(credentialsListProvider);
                    },
                    child: const Text('Unlock'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

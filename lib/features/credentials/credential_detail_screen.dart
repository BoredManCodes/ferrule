import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets.dart';
import 'credential_repository.dart';

class CredentialDetailScreen extends ConsumerStatefulWidget {
  final int id;
  const CredentialDetailScreen({super.key, required this.id});

  @override
  ConsumerState<CredentialDetailScreen> createState() =>
      _CredentialDetailScreenState();
}

class _CredentialDetailScreenState
    extends ConsumerState<CredentialDetailScreen> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(credentialProvider(widget.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.value?.name ?? 'Credential'),
        actions: [
          if (async.value != null)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/credentials/${widget.id}/edit'),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(credentialProvider(widget.id))),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(c.name ?? '(unnamed)',
                                style: Theme.of(context).textTheme.titleLarge),
                          ),
                          if (c.favorite)
                            const Icon(Icons.star, color: Colors.amber),
                        ],
                      ),
                      if (c.description != null) ...[
                        const SizedBox(height: 4),
                        Text(c.description!,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    if (c.username != null)
                      _Field(
                        label: 'Username',
                        value: c.username!,
                        icon: Icons.person_outline,
                        onCopy: () => _copy(context, c.username!, 'Username'),
                      ),
                    if (c.password != null) ...[
                      const Divider(height: 1),
                      _Field(
                        label: 'Password',
                        value: _revealed
                            ? c.password!
                            : '•' * c.password!.length.clamp(8, 16),
                        icon: Icons.lock_outline,
                        monospace: _revealed,
                        onCopy: () => _copy(context, c.password!, 'Password'),
                        trailing: IconButton(
                          icon: Icon(_revealed
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _revealed = !_revealed),
                        ),
                      ),
                    ],
                    if (c.otpSecret != null) ...[
                      const Divider(height: 1),
                      _Field(
                        label: 'OTP Secret',
                        value: '•••••• (tap to copy)',
                        icon: Icons.shield_outlined,
                        onCopy: () =>
                            _copy(context, c.otpSecret!, 'OTP secret'),
                      ),
                    ],
                    if (c.uri != null) ...[
                      const Divider(height: 1),
                      _Field(
                        label: 'URL',
                        value: c.uri!,
                        icon: Icons.link,
                        onTap: () => _open(c.uri!),
                        trailing: const Icon(Icons.open_in_new, size: 18),
                      ),
                    ],
                    if (c.uri2 != null) ...[
                      const Divider(height: 1),
                      _Field(
                        label: 'URL 2',
                        value: c.uri2!,
                        icon: Icons.link,
                        onTap: () => _open(c.uri2!),
                      ),
                    ],
                  ],
                ),
              ),
              if (c.note != null) ...[
                const SectionHeader('Note'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(c.note!),
                    ),
                  ),
                ),
              ],
              if (c.passwordChangedAt != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Password changed ${DateFormat.yMMMd().format(c.passwordChangedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _copy(BuildContext context, String value, String name) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name copied'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _open(String uri) async {
    var s = uri;
    if (!s.startsWith('http')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u != null) await launchUrl(u);
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onCopy;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool monospace;
  const _Field({
    required this.label,
    required this.value,
    required this.icon,
    this.onCopy,
    this.onTap,
    this.trailing,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? onCopy,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          )),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontFamily: monospace ? 'monospace' : null,
                        ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (trailing == null && onCopy != null)
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: onCopy,
              ),
          ],
        ),
      ),
    );
  }
}

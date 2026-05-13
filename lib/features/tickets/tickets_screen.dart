import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets.dart';
import 'ticket_model.dart';
import 'ticket_repository.dart';

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  String _filter = 'open';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ticketsProvider);
    final loadProgress = ref.watch(ticketLoadProgressProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tickets'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(ticketsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/tickets/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Ticket'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search tickets…',
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                for (final f in const ['open', 'resolved', 'all'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f[0].toUpperCase() + f.substring(1)),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      loadProgress > 0
                          ? 'Loaded $loadProgress tickets…'
                          : 'Loading tickets…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(ticketsProvider),
              ),
              data: (tickets) {
                final filtered = tickets.where((t) {
                  if (_filter == 'open' && t.isResolved) return false;
                  if (_filter == 'resolved' && !t.isResolved) return false;
                  if (_search.isEmpty) return true;
                  final hay =
                      '${t.subject ?? ''} ${t.displayNumber} ${t.details ?? ''}'
                          .toLowerCase();
                  return hay.contains(_search);
                }).toList()
                  ..sort((a, b) => b.id.compareTo(a.id));
                if (filtered.isEmpty) {
                  return EmptyView(
                    icon: Icons.confirmation_number_outlined,
                    title: 'No tickets',
                    message: _filter == 'open'
                        ? 'No open tickets — nice work.'
                        : 'Nothing matches.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(ticketsProvider),
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _TicketTile(ticket: filtered[i]),
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

class _TicketTile extends StatelessWidget {
  final Ticket ticket;
  const _TicketTile({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final priorityColor = switch (ticket.priority?.toLowerCase()) {
      'critical' => Colors.red,
      'high' => Colors.orange,
      'medium' => Colors.amber,
      'low' => Colors.green,
      _ => scheme.onSurfaceVariant,
    };
    return ListTile(
      onTap: () => context.push('/tickets/${ticket.id}'),
      leading: CircleAvatar(
        backgroundColor: priorityColor.withValues(alpha: 0.15),
        child: Icon(
          ticket.isResolved
              ? Icons.check_circle_outline
              : Icons.confirmation_number_outlined,
          color: ticket.isResolved ? Colors.green : priorityColor,
        ),
      ),
      title: Text(
        ticket.subject ?? '(no subject)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Text(ticket.displayNumber),
          const Text(' • '),
          Text(ticket.priority ?? 'Medium',
              style: TextStyle(color: priorityColor)),
          if (ticket.createdAt != null) ...[
            const Text(' • '),
            Text(DateFormat.MMMd().format(ticket.createdAt!)),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

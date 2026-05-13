import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/providers.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../clients/client_repository.dart';
import '../timer/log_reply_sheet.dart';
import '../timer/timer_state.dart';
import 'reply_model.dart';
import 'ticket_model.dart';
import 'ticket_repository.dart';

class TicketDetailScreen extends ConsumerWidget {
  final int id;
  const TicketDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ticketProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.value?.displayNumber ?? 'Ticket'),
        actions: [
          if (async.value != null)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/tickets/$id/edit'),
            ),
          if (async.value != null)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(ticketProvider(id));
                ref.invalidate(ticketRepliesProvider(id));
              },
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(ticketProvider(id)),
        ),
        data: (ticket) {
          if (ticket == null) {
            return const EmptyView(
              icon: Icons.search_off,
              title: 'Ticket not found',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(ticketProvider(id));
              ref.invalidate(ticketRepliesProvider(id));
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeaderCard(ticket: ticket),
                const SizedBox(height: 12),
                _MetaCard(ticket: ticket),
                const SizedBox(height: 12),
                _SubjectDetailsCard(ticket: ticket),
                const SizedBox(height: 16),
                _Actions(ticket: ticket),
                const SizedBox(height: 24),
                Text('Replies',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _RepliesList(ticketId: ticket.id),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Ticket ticket;
  const _HeaderCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.support_agent_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ticket ${ticket.displayNumber}',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _StatusBadge(ticket: ticket),
                      const SizedBox(width: 6),
                      _PriorityBadge(priority: ticket.priority),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Ticket ticket;
  const _StatusBadge({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final name = ticket.statusName ??
        (ticket.isResolved
            ? 'Resolved'
            : (ticket.statusId == 1
                ? 'New'
                : ticket.statusId == 2
                    ? 'Open'
                    : ticket.statusId == 3
                        ? 'In Progress'
                        : 'Open'));
    Color color;
    switch (name.toLowerCase()) {
      case 'new':
        color = Colors.pink;
        break;
      case 'open':
        color = Colors.blue;
        break;
      case 'in progress':
        color = Colors.amber.shade700;
        break;
      case 'on hold':
      case 'waiting':
        color = Colors.grey;
        break;
      case 'closed':
      case 'resolved':
        color = Colors.green;
        break;
      default:
        color = Theme.of(context).colorScheme.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        name,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String? priority;
  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    if (priority == null) return const SizedBox.shrink();
    Color color;
    switch (priority!.toLowerCase()) {
      case 'critical':
        color = Colors.red;
        break;
      case 'high':
        color = Colors.deepOrange;
        break;
      case 'medium':
        color = Colors.amber.shade700;
        break;
      default:
        color = Colors.green;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        priority!,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MetaCard extends ConsumerWidget {
  final Ticket ticket;
  const _MetaCard({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = toDate(ticket.raw['ticket_due_at']);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetaRow(
              icon: Icons.person_outline,
              label: 'Agent',
              value: (ticket.assignedTo == null || ticket.assignedTo == 0)
                  ? 'Unassigned'
                  : 'User #${ticket.assignedTo}',
              muted: (ticket.assignedTo == null || ticket.assignedTo == 0),
            ),
            const Divider(height: 20),
            _MetaRow(
              icon: Icons.schedule,
              label: 'Scheduled',
              value: due != null
                  ? DateFormat.yMMMd().add_jm().format(due)
                  : 'Not scheduled',
              muted: due == null,
            ),
            const Divider(height: 20),
            _MetaRow(
              icon: Icons.attach_money,
              label: 'Billable',
              value: ticket.billable ? 'Yes' : 'No',
              valueColor: ticket.billable ? Colors.green : null,
            ),
            if (ticket.clientId != null && ticket.clientId! > 0) ...[
              const Divider(height: 20),
              Consumer(
                builder: (context, ref, _) {
                  final clientsAsync = ref.watch(clientsProvider);
                  final name = clientsAsync.maybeWhen(
                    data: (list) {
                      final c = list.where((c) => c.id == ticket.clientId);
                      return c.isEmpty
                          ? 'Client #${ticket.clientId}'
                          : (c.first.name ?? 'Client #${ticket.clientId}');
                    },
                    orElse: () => 'Client #${ticket.clientId}',
                  );
                  return InkWell(
                    onTap: () => context.push('/clients/${ticket.clientId}'),
                    child: _MetaRow(
                      icon: Icons.business_outlined,
                      label: 'Client',
                      value: name,
                      trailing: Icon(Icons.chevron_right,
                          size: 18, color: scheme.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ],
            if (ticket.source != null) ...[
              const Divider(height: 20),
              _MetaRow(
                icon: Icons.input,
                label: 'Source',
                value: ticket.source!,
              ),
            ],
            if (ticket.createdAt != null) ...[
              const Divider(height: 20),
              _MetaRow(
                icon: Icons.access_time,
                label: 'Created',
                value: DateFormat.yMMMd().add_jm().format(ticket.createdAt!),
              ),
            ],
            if (ticket.resolvedAt != null) ...[
              const Divider(height: 20),
              _MetaRow(
                icon: Icons.check_circle_outline,
                label: 'Resolved',
                value: DateFormat.yMMMd().add_jm().format(ticket.resolvedAt!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  final Color? valueColor;
  final Widget? trailing;
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Fixed-width label column so every row's value lines up at the same X,
    // regardless of label or value length.
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: muted
                  ? scheme.onSurfaceVariant
                  : (valueColor ?? scheme.onSurface),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
      ],
    );
  }
}

class _SubjectDetailsCard extends StatelessWidget {
  final Ticket ticket;
  const _SubjectDetailsCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Strip HTML and whitespace before deciding to render the body — the API
    // auto-appends `<br>` to details on create, which would otherwise render
    // an empty padded card.
    final detailsText = (ticket.details ?? '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final hasDetails = detailsText.isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
            child: Text(
              ticket.subject ?? '(no subject)',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (hasDetails)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Html(
                data: ticket.details!,
                style: {
                  'body': Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                    color: scheme.onSurface,
                  ),
                  'a': Style(
                    color: scheme.primary,
                    textDecoration: TextDecoration.underline,
                  ),
                  'p': Style(margin: Margins.only(bottom: 8)),
                  'pre': Style(
                    backgroundColor: scheme.surfaceContainerHighest,
                    padding: HtmlPaddings.all(8),
                    fontFamily: 'monospace',
                  ),
                  'code': Style(
                    backgroundColor: scheme.surfaceContainerHighest,
                    fontFamily: 'monospace',
                  ),
                },
                onLinkTap: (url, _, __) {
                  if (url != null) launchUrl(Uri.parse(url));
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  final Ticket ticket;
  const _Actions({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () async {
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => LogReplySheet(
                ticketId: ticket.id,
                ticketLabel:
                    '${ticket.displayNumber} — ${ticket.subject ?? ''}',
                duration: Duration.zero,
              ),
            );
            ref.invalidate(ticketRepliesProvider(ticket.id));
          },
          icon: const Icon(Icons.reply),
          label: const Text('Reply'),
        ),
        FilledButton.tonalIcon(
          onPressed: () async {
            await ref.read(activeTimerProvider.notifier).start(
                  ticket.id,
                  label:
                      '${ticket.displayNumber} — ${ticket.subject ?? ''}',
                );
            if (context.mounted) context.push('/timer');
          },
          icon: const Icon(Icons.timer_outlined),
          label: const Text('Start Timer'),
        ),
        if (!ticket.isResolved)
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await ref
                  .read(ticketRepositoryProvider)
                  .resolve(ticket.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        ok ? 'Ticket resolved' : 'Could not resolve ticket'),
                  ),
                );
                if (ok) {
                  ref.invalidate(ticketProvider(ticket.id));
                  ref.invalidate(ticketsProvider);
                }
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Resolve'),
          ),
      ],
    );
  }
}

class _RepliesList extends ConsumerWidget {
  final int ticketId;
  const _RepliesList({required this.ticketId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasWeb = ref.watch(itflowWebClientProvider) != null;
    if (!hasWeb) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.lock_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Replies aren\'t available — set agent email + password in Settings to load the conversation thread.',
                ),
              ),
            ],
          ),
        ),
      );
    }
    final replies = ref.watch(ticketRepliesProvider(ticketId));
    return replies.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Could not load replies: $e',
              style: const TextStyle(fontSize: 12)),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No replies yet')),
            ),
          );
        }
        return Column(
          children: [
            for (final r in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ReplyCard(reply: r),
              ),
          ],
        );
      },
    );
  }
}

class _ReplyCard extends StatelessWidget {
  final TicketReply reply;
  const _ReplyCard({required this.reply});

  Color get _borderColor {
    switch (reply.type) {
      case ReplyType.internal:
        return const Color(0xFF343A40);
      case ReplyType.client:
        return Colors.amber;
      case ReplyType.public:
        return const Color(0xFF17A2B8);
    }
  }

  String get _typeLabel {
    switch (reply.type) {
      case ReplyType.internal:
        return 'Internal';
      case ReplyType.client:
        return 'Client';
      case ReplyType.public:
        return 'Public';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: _borderColor),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: scheme.surfaceContainerHighest,
                            child: Text(
                              reply.authorInitials ?? '?',
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(reply.authorName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            height: 1.2)),
                                if (reply.hasTimeWorked)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.timer_outlined,
                                            size: 12,
                                            color: scheme.onSurfaceVariant),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Time worked: ${reply.timeWorked!}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Match the author-name line so the type/time-ago label
                          // aligns with "Author Name" rather than drifting down.
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              // ITFlow's createdAgo already contains the type
                              // prefix ("Internal - X ago"), so use it as-is
                              // and only fall back to the type label.
                              reply.createdAgo ?? _typeLabel,
                              textAlign: TextAlign.right,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Html(
                        data: reply.bodyHtml,
                        style: {
                          'body': Style(
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                            color: scheme.onSurface,
                          ),
                          'p': Style(margin: Margins.only(bottom: 6)),
                          'a': Style(
                            color: scheme.primary,
                            textDecoration: TextDecoration.underline,
                          ),
                        },
                        onLinkTap: (url, _, __) {
                          if (url != null) launchUrl(Uri.parse(url));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

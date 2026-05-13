import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/providers.dart';
import '../../core/widgets.dart';
import '../tickets/ticket_model.dart';
import '../tickets/ticket_repository.dart';
import 'log_reply_sheet.dart';
import 'time_log_history.dart';
import 'timer_state.dart';

class TimerScreen extends ConsumerWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(activeTimerProvider);
    final history = ref.watch(timeLogHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Labour Timer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          timer.when(
            loading: () => const _LoadingCard(),
            error: (e, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$e'),
              ),
            ),
            data: (active) => active == null
                ? _StartCard()
                : _RunningCard(active: active),
          ),
          const SizedBox(height: 24),
          Text('Recent Logs',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          history.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
            data: (list) {
              if (list.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('No time logged yet on this device.')),
                  ),
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: list[i].submitted
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.15),
                          child: Icon(
                            list[i].submitted
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            color: list[i].submitted
                                ? Colors.green
                                : Colors.orange,
                            size: 18,
                          ),
                        ),
                        title: Text(
                            list[i].ticketLabel ?? 'Ticket #${list[i].ticketId}'),
                        subtitle: Text(
                          '${formatDuration(list[i].duration)}'
                          ' • ${DateFormat.yMd().add_jm().format(list[i].loggedAt)}',
                        ),
                        trailing: list[i].submitted
                            ? null
                            : const Text('local',
                                style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => const Card(
        child: SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
}

class _StartCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(ticketsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Start a timer',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Pick a ticket to track time against. The timer keeps running even if you close the app.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            tickets.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.invalidate(ticketsProvider)),
              data: (list) {
                final open = list.where((t) => !t.isResolved).toList();
                return FilledButton.icon(
                  onPressed: open.isEmpty
                      ? null
                      : () async {
                          final ticket = await showModalBottomSheet<Ticket>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => _TicketPicker(tickets: open),
                          );
                          if (ticket == null) return;
                          await ref
                              .read(activeTimerProvider.notifier)
                              .start(
                                ticket.id,
                                label:
                                    '${ticket.displayNumber} — ${ticket.subject ?? ''}',
                              );
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(open.isEmpty
                      ? 'No open tickets'
                      : 'Start timer on a ticket…'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketPicker extends StatefulWidget {
  final List<Ticket> tickets;
  const _TicketPicker({required this.tickets});

  @override
  State<_TicketPicker> createState() => _TicketPickerState();
}

class _TicketPickerState extends State<_TicketPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.tickets.where((t) {
      if (_search.isEmpty) return true;
      final hay =
          '${t.subject ?? ''} ${t.displayNumber}'.toLowerCase();
      return hay.contains(_search);
    }).toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('Pick a ticket',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = filtered[i];
                    return ListTile(
                      onTap: () => Navigator.of(context).pop(t),
                      title: Text(t.subject ?? '(no subject)',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(t.displayNumber),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RunningCard extends ConsumerStatefulWidget {
  final ActiveTimer active;
  const _RunningCard({required this.active});

  @override
  ConsumerState<_RunningCard> createState() => _RunningCardState();
}

class _RunningCardState extends ConsumerState<_RunningCard> {
  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final scheme = Theme.of(context).colorScheme;
    // Re-render every second while the timer is running.
    ref.watch(timerTickProvider);
    final elapsed = active.elapsed();
    final webConfigured =
        ref.watch(itflowWebClientProvider) != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: active.running ? Colors.red : Colors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(active.running ? 'Running' : 'Paused',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            Text(active.ticketLabel ?? 'Ticket #${active.ticketId}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Center(
              child: Text(
                formatDuration(elapsed),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: active.running
                        ? () =>
                            ref.read(activeTimerProvider.notifier).pause()
                        : () =>
                            ref.read(activeTimerProvider.notifier).resume(),
                    icon: Icon(active.running
                        ? Icons.pause
                        : Icons.play_arrow),
                    label: Text(active.running ? 'Pause' : 'Resume'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final duration = active.elapsed();
                      await ref.read(activeTimerProvider.notifier).pause();
                      if (!context.mounted) return;
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => LogReplySheet(
                          ticketId: active.ticketId,
                          ticketLabel: active.ticketLabel,
                          duration: duration,
                        ),
                      );
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop & Log'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('Discard timer?'),
                    content: Text(
                        '${formatDuration(elapsed)} will be lost.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogCtx, false),
                          child: const Text('Cancel')),
                      FilledButton.tonal(
                          onPressed: () => Navigator.pop(dialogCtx, true),
                          child: const Text('Discard')),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(activeTimerProvider.notifier).discard();
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Discard'),
            ),
            if (!webConfigured) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: scheme.onErrorContainer, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Add agent email + password in Settings to submit time to ITFlow. Otherwise the log is kept locally.',
                        style: TextStyle(
                          color: scheme.onErrorContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

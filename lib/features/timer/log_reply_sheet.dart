import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/widgets/ai_reword_button.dart';
import '../tickets/ticket_repository.dart';
import 'time_log_history.dart';
import 'timer_state.dart';

class LogReplySheet extends ConsumerStatefulWidget {
  final int ticketId;
  final String? ticketLabel;
  final Duration duration;

  /// When true, the sheet presents itself as a reply flow: title "Reply",
  /// reply text first, time worked tucked into an optional secondary
  /// section, no "Save Locally" button, and a REST fallback so users
  /// without agent credentials can still post Internal or Public-no-email
  /// replies. When false (the timer flow), behaves as the original
  /// "Log time" sheet.
  final bool replyOnly;

  const LogReplySheet({
    super.key,
    required this.ticketId,
    this.ticketLabel,
    required this.duration,
    this.replyOnly = false,
  });

  @override
  ConsumerState<LogReplySheet> createState() => _LogReplySheetState();
}

class _LogReplySheetState extends ConsumerState<LogReplySheet> {
  late Duration _duration = widget.duration;
  final _reply = TextEditingController();
  int _replyType = 3; // Internal by default — safest
  int _statusId = 3; // In Progress
  bool _busy = false;
  String? _error;
  bool _timeExpanded = false; // reply-only: collapsed until user taps

  static const _statuses = {
    1: 'New',
    2: 'Open',
    3: 'In Progress',
    4: 'Closed',
  };

  static const _replyTypes = {
    3: 'Internal note',
    1: 'Public reply (no email)',
    2: 'Public reply + email',
  };

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _editDuration() async {
    final picked = await showDialog<Duration>(
      context: context,
      builder: (_) => _DurationDialog(initial: _duration),
    );
    if (picked != null) setState(() => _duration = picked);
  }

  Future<void> _submit({required bool postToItflow}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final h = _duration.inHours;
    final m = _duration.inMinutes % 60;
    final s = _duration.inSeconds % 60;
    try {
      if (postToItflow) {
        final web = ref.read(itflowWebClientProvider);
        // Prefer the REST endpoint when:
        //   - web credentials aren't set (REST is the only option), or
        //   - the user picked a reply type the REST endpoint supports
        //     (Internal=3 or Public-no-email=1; Public+email=2 must go
        //     through the web client because the REST endpoint refuses
        //     to dispatch mail).
        final canUseRest = _replyType != 2;
        if (web == null && canUseRest) {
          final result = await ref
              .read(ticketRepositoryProvider)
              .addReply(
                ticketId: widget.ticketId,
                body: _reply.text,
                replyType: _replyType,
                status: _statusId,
                timeWorked: _duration,
              );
          if (!result.ok) {
            throw StateError(result.error ?? 'Reply failed.');
          }
        } else if (web != null) {
          // Need the ticket's client_id to satisfy the form.
          final ticket =
              await ref.read(ticketRepositoryProvider).get(widget.ticketId);
          final clientId = ticket?.clientId ?? 0;
          await web.addTicketReply(
            ticketId: widget.ticketId,
            clientId: clientId,
            statusId: _statusId,
            hours: h,
            minutes: m,
            seconds: s,
            replyText: _reply.text,
            replyType: _replyType,
          );
        } else {
          throw StateError(
              'Public + email replies need agent email + password in Settings.');
        }
      }
      // Only log to the local time-log history when there's actually time
      // to record. A pure reply with no duration isn't a time-log entry.
      if (_duration > Duration.zero) {
        await ref.read(timeLogHistoryProvider.notifier).add(
              TimeLogEntry(
                ticketId: widget.ticketId,
                ticketLabel: widget.ticketLabel,
                loggedAt: DateTime.now(),
                duration: _duration,
                submitted: postToItflow,
                note: _reply.text.isEmpty ? null : _reply.text,
              ),
            );
      }
      await ref.read(activeTimerProvider.notifier).discard();
      if (postToItflow) {
        ref.invalidate(ticketsProvider);
        ref.invalidate(ticketProvider(widget.ticketId));
        ref.invalidate(ticketRepliesProvider(widget.ticketId));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_successMessage(postToItflow)),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _successMessage(bool postToItflow) {
    if (!postToItflow) return 'Saved locally';
    if (widget.replyOnly) return 'Reply posted';
    return 'Time logged to ITFlow';
  }

  Future<void> _copyDuration() async {
    final h = _duration.inHours;
    final m = _duration.inMinutes % 60;
    final s = _duration.inSeconds % 60;
    final formatted =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    await Clipboard.setData(ClipboardData(text: formatted));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied $formatted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasWeb = ref.watch(itflowWebClientProvider) != null;
    // REST can handle Internal + Public-no-email without web creds. Submit
    // is only truly disabled when the user picked Public + email AND there
    // are no web creds to fall back on.
    final canSubmit = hasWeb || _replyType != 2;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(widget.replyOnly ? 'Reply' : 'Log time',
                  style: Theme.of(context).textTheme.titleLarge),
              if (widget.ticketLabel != null) ...[
                const SizedBox(height: 4),
                Text(widget.ticketLabel!,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 16),
              if (!widget.replyOnly) _timeTile(context),
              if (!widget.replyOnly) const SizedBox(height: 16),
              TextField(
                controller: _reply,
                maxLines: 5,
                minLines: widget.replyOnly ? 4 : 3,
                autofocus: widget.replyOnly,
                decoration: InputDecoration(
                  labelText: widget.replyOnly
                      ? 'Reply'
                      : 'Reply text (optional for internal note)',
                  alignLabelWithHint: true,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: AiRewordButton(controller: _reply),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _replyType,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Reply type'),
                      items: [
                        for (final e in _replyTypes.entries)
                          DropdownMenuItem(
                              value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) =>
                          setState(() => _replyType = v ?? 3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _statusId,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Status'),
                      items: [
                        for (final e in _statuses.entries)
                          DropdownMenuItem(
                              value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) =>
                          setState(() => _statusId = v ?? 3),
                    ),
                  ),
                ],
              ),
              if (widget.replyOnly) ...[
                const SizedBox(height: 8),
                _ExpandableTimeSection(
                  expanded: _timeExpanded,
                  duration: _duration,
                  onToggle: () =>
                      setState(() => _timeExpanded = !_timeExpanded),
                  onEdit: _editDuration,
                  onCopy: _copyDuration,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      )),
                ),
              ],
              const SizedBox(height: 20),
              if (widget.replyOnly)
                FilledButton.icon(
                  onPressed: _busy || !canSubmit
                      ? null
                      : () => _submit(postToItflow: true),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_outlined),
                  label: Text(_busy ? 'Posting…' : 'Post reply'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _submit(postToItflow: false),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save Locally'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy || !canSubmit
                            ? null
                            : () => _submit(postToItflow: true),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(_busy ? 'Submitting…' : 'Submit'),
                      ),
                    ),
                  ],
                ),
              if (!hasWeb && _replyType == 2) ...[
                const SizedBox(height: 8),
                Text(
                  'Public + email needs agent email + password in Settings. Pick Internal or Public (no email) to post via the REST API.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeTile(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _editDuration,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      formatDuration(_duration),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                    ),
                  ),
                  const Icon(Icons.edit, size: 18),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: _copyDuration,
          icon: const Icon(Icons.copy),
          tooltip: 'Copy HH:MM:SS',
        ),
      ],
    );
  }
}

class _ExpandableTimeSection extends StatelessWidget {
  final bool expanded;
  final Duration duration;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  const _ExpandableTimeSection({
    required this.expanded,
    required this.duration,
    required this.onToggle,
    required this.onEdit,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final hasTime = duration > Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    hasTime
                        ? 'Time worked: ${formatDuration(duration)}'
                        : 'Add time worked (optional)',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            formatDuration(duration),
                            style:
                                Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                          ),
                        ),
                        const Icon(Icons.edit, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onCopy,
                icon: const Icon(Icons.copy),
                tooltip: 'Copy HH:MM:SS',
              ),
            ],
          ),
      ],
    );
  }
}

class _DurationDialog extends StatefulWidget {
  final Duration initial;
  const _DurationDialog({required this.initial});

  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  late int _h = widget.initial.inHours;
  late int _m = widget.initial.inMinutes % 60;
  late int _s = widget.initial.inSeconds % 60;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit duration'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NumberField(label: 'h', value: _h, max: 99, onChanged: (v) => _h = v),
          const SizedBox(width: 8),
          _NumberField(label: 'm', value: _m, max: 59, onChanged: (v) => _m = v),
          const SizedBox(width: 8),
          _NumberField(label: 's', value: _s, max: 59, onChanged: (v) => _s = v),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, Duration(hours: _h, minutes: _m, seconds: _s)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: TextFormField(
        initialValue: value.toString(),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        onChanged: (v) {
          final n = int.tryParse(v) ?? 0;
          onChanged(n.clamp(0, max));
        },
      ),
    );
  }
}

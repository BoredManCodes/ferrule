import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/providers.dart';
import '../../core/widgets.dart';
import '../../core/widgets/ai_reword_button.dart';
import '../clients/client_repository.dart';
import 'ticket_repository.dart';

class EditTicketScreen extends ConsumerStatefulWidget {
  final int ticketId;
  const EditTicketScreen({super.key, required this.ticketId});

  @override
  ConsumerState<EditTicketScreen> createState() => _EditTicketScreenState();
}

class _EditTicketScreenState extends ConsumerState<EditTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _details = TextEditingController();
  String _priority = 'Medium';
  int? _clientId;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    final ticket =
        await ref.read(ticketRepositoryProvider).get(widget.ticketId);
    if (!mounted || ticket == null) return;
    setState(() {
      _subject.text = ticket.subject ?? '';
      _details.text = ticket.details ?? '';
      _priority = ticket.priority ?? 'Medium';
      _clientId = ticket.clientId;
      _loaded = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref.read(ticketRepositoryProvider).edit(
          ticketId: widget.ticketId,
          subject: _subject.text.trim(),
          details: _details.text,
          priority: _priority,
          newClientId: _clientId,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      ref.invalidate(ticketProvider(widget.ticketId));
      ref.invalidate(ticketsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket updated')),
      );
      context.pop();
    } else {
      setState(() => _error = r.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider);
    final hasWeb = ref.watch(itflowWebClientProvider) != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Ticket')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!hasWeb) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Editing requires agent email + password. Add them in Settings (Web Session).',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _subject,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      prefixIcon: Icon(Icons.title),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _details,
                    maxLines: 10,
                    minLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Details',
                      helperText:
                          'Rich formatting uses HTML — use <br> for line breaks',
                      alignLabelWithHint: true,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AiRewordButton(controller: _details),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Low', child: Text('Low')),
                      DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'High', child: Text('High')),
                      DropdownMenuItem(
                          value: 'Critical', child: Text('Critical')),
                    ],
                    onChanged: (v) =>
                        setState(() => _priority = v ?? 'Medium'),
                  ),
                  const SizedBox(height: 12),
                  clients.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => ErrorView(error: e),
                    data: (list) => DropdownButtonFormField<int>(
                      initialValue: list.any((c) => c.id == _clientId)
                          ? _clientId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Client',
                        helperText:
                            'Changing the client clears the assigned contact',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      items: [
                        for (final c in list)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.name ?? 'Client #${c.id}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _clientId = v),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy || !hasWeb ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_busy ? 'Saving…' : 'Save Changes'),
                  ),
                ],
              ),
            ),
    );
  }
}

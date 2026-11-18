import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/ai_reword_button.dart';
import '../clients/client_repository.dart';
import '../contacts/contact_repository.dart';
import 'ticket_repository.dart';

class CreateTicketScreen extends ConsumerStatefulWidget {
  /// Client to start with, e.g. when opened from a client's page.
  final int? initialClientId;
  const CreateTicketScreen({super.key, this.initialClientId});

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _detailsController = TextEditingController();
  String _priority = 'Medium';
  bool _billable = false;
  bool _busy = false;
  late int? _clientId = widget.initialClientId;
  int? _contactId;

  @override
  void dispose() {
    _subjectController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(ticketRepositoryProvider).create(
            subject: _subjectController.text.trim(),
            details: _detailsController.text.trim(),
            priority: _priority,
            billable: _billable,
            clientId: _clientId ?? 0,
            contactId: _contactId ?? 0,
          );
      if (!mounted) return;
      if (result.id != null) {
        ref.invalidate(ticketsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ticket #${result.id} created')),
        );
        // Replace the create-screen route with the new ticket's detail.
        context.pushReplacement('/tickets/${result.id}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(result.error ?? 'Failed to create ticket')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _clientPicker() {
    final clients = ref.watch(clientsProvider);
    final list = clients.value ?? const [];
    return DropdownButtonFormField<int>(
      key: ValueKey('clients-${list.length}'),
      initialValue: list.any((c) => c.id == _clientId) ? _clientId : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Client',
        prefixIcon: const Icon(Icons.business_outlined),
        helperText: clients.isLoading ? 'Loading clients…' : null,
      ),
      items: [
        for (final c in list)
          DropdownMenuItem(
            value: c.id,
            child: Text(c.name ?? 'Client #${c.id}',
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() {
        _clientId = v;
        _contactId = null;
      }),
    );
  }

  Widget _contactPicker() {
    final all = ref.watch(contactsProvider).value ?? const [];
    final list = _clientId == null
        ? const []
        : all.where((c) => c.clientId == _clientId).toList();
    return DropdownButtonFormField<int>(
      key: ValueKey('contacts-$_clientId-${list.length}'),
      initialValue: list.any((c) => c.id == _contactId) ? _contactId : null,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Contact',
        prefixIcon: Icon(Icons.person_outline),
        helperText: "Left empty, ITFlow picks the client's primary contact",
      ),
      items: [
        for (final c in list)
          DropdownMenuItem(
            value: c.id,
            child: Text(c.name ?? 'Contact #${c.id}',
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _clientId == null ? null : (v) => setState(() => _contactId = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Ticket')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _subjectController,
              decoration: const InputDecoration(
                labelText: 'Subject',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _detailsController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Details',
                alignLabelWithHint: true,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: AiRewordButton(controller: _detailsController),
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
                DropdownMenuItem(value: 'Critical', child: Text('Critical')),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'Medium'),
            ),
            const SizedBox(height: 12),
            _clientPicker(),
            const SizedBox(height: 12),
            _contactPicker(),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _billable,
              onChanged: (v) => setState(() => _billable = v),
              title: const Text('Billable'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_busy ? 'Creating…' : 'Create Ticket'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../clients/client_repository.dart';
import 'credential_repository.dart';

class CredentialFormScreen extends ConsumerStatefulWidget {
  final int? credentialId;
  const CredentialFormScreen({super.key, this.credentialId});

  @override
  ConsumerState<CredentialFormScreen> createState() =>
      _CredentialFormScreenState();
}

class _CredentialFormScreenState extends ConsumerState<CredentialFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _uri = TextEditingController();
  final _uri2 = TextEditingController();
  final _otpSecret = TextEditingController();
  final _note = TextEditingController();
  bool _favorite = false;
  int? _clientId;
  bool _showPw = false;
  bool _busy = false;
  bool _loaded = false;

  bool get _isEdit => widget.credentialId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _hydrate();
    } else {
      _loaded = true;
    }
  }

  Future<void> _hydrate() async {
    final c =
        await ref.read(credentialRepositoryProvider).get(widget.credentialId!);
    if (!mounted || c == null) return;
    setState(() {
      _name.text = c.name ?? '';
      _description.text = c.description ?? '';
      _username.text = c.username ?? '';
      _password.text = c.password ?? '';
      _uri.text = c.uri ?? '';
      _uri2.text = c.uri2 ?? '';
      _otpSecret.text = c.otpSecret ?? '';
      _note.text = c.note ?? '';
      _favorite = c.favorite;
      _clientId = c.clientId;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _username,
      _password,
      _uri,
      _uri2,
      _otpSecret,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final data = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'username': _username.text.trim(),
      'password': _password.text,
      'uri': _uri.text.trim(),
      'uri_2': _uri2.text.trim(),
      'otp_secret': _otpSecret.text.trim(),
      'note': _note.text.trim(),
      'favorite': _favorite ? 1 : 0,
      if (_clientId != null) 'client_id': _clientId,
    };
    try {
      final repo = ref.read(credentialRepositoryProvider);
      bool ok;
      String? error;
      if (_isEdit) {
        final r = await repo.update(widget.credentialId!, data);
        ok = r.ok;
        error = r.error;
      } else {
        final r = await repo.create(data);
        ok = r.id != null;
        error = r.error;
      }
      if (!mounted) return;
      if (ok) {
        ref.invalidate(credentialsListProvider);
        if (_isEdit) {
          ref.invalidate(credentialProvider(widget.credentialId!));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? 'Saved' : 'Created')),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Save failed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider);
    return Scaffold(
      appBar:
          AppBar(title: Text(_isEdit ? 'Edit Credential' : 'New Credential')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    decoration:
                        const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: !_showPw,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_showPw
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () => setState(() => _showPw = !_showPw),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _uri,
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _uri2,
                    decoration: const InputDecoration(
                      labelText: 'URL 2 (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _otpSecret,
                    decoration: const InputDecoration(
                      labelText: 'OTP Secret',
                      prefixIcon: Icon(Icons.shield_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  clients.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (list) => DropdownButtonFormField<int>(
                      initialValue: _clientId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Client',
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
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _note,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _favorite,
                    onChanged: (v) => setState(() => _favorite = v),
                    title: const Text('Favorite'),
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
                    label: Text(_busy ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ),
    );
  }
}

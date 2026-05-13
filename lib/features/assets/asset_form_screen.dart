import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../clients/client_repository.dart';
import 'asset_model.dart';
import 'asset_repository.dart';

class AssetFormScreen extends ConsumerStatefulWidget {
  final int? assetId;
  const AssetFormScreen({super.key, this.assetId});

  @override
  ConsumerState<AssetFormScreen> createState() => _AssetFormScreenState();
}

class _AssetFormScreenState extends ConsumerState<AssetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _os = TextEditingController();
  final _uri = TextEditingController();
  final _ip = TextEditingController();
  final _mac = TextEditingController();
  final _notes = TextEditingController();
  String? _type;
  String? _status;
  int? _clientId;
  bool _busy = false;
  bool _loaded = false;

  bool get _isEdit => widget.assetId != null;

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
    final asset = await ref.read(assetRepositoryProvider).get(widget.assetId!);
    if (!mounted || asset == null) return;
    setState(() {
      _name.text = asset.name ?? '';
      _description.text = asset.description ?? '';
      _make.text = asset.make ?? '';
      _model.text = asset.model ?? '';
      _serial.text = asset.serial ?? '';
      _os.text = asset.os ?? '';
      _uri.text = asset.uri ?? '';
      _ip.text = asset.ip ?? '';
      _mac.text = asset.mac ?? '';
      _notes.text = asset.notes ?? '';
      _type = asset.type;
      _status = asset.status;
      _clientId = asset.clientId;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _make,
      _model,
      _serial,
      _os,
      _uri,
      _ip,
      _mac,
      _notes,
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
      'type': _type ?? '',
      'make': _make.text.trim(),
      'model': _model.text.trim(),
      'serial': _serial.text.trim(),
      'os': _os.text.trim(),
      'uri': _uri.text.trim(),
      'status': _status ?? '',
      'ip': _ip.text.trim(),
      'mac': _mac.text.trim(),
      'notes': _notes.text.trim(),
      if (_clientId != null) 'client_id': _clientId,
    };
    try {
      final repo = ref.read(assetRepositoryProvider);
      String? error;
      bool ok;
      if (_isEdit) {
        final r = await repo.update(widget.assetId!, data);
        ok = r.ok;
        error = r.error;
      } else {
        final r = await repo.create(data);
        ok = r.id != null;
        error = r.error;
      }
      if (!mounted) return;
      if (ok) {
        ref.invalidate(assetsProvider);
        if (_isEdit) ref.invalidate(assetProvider(widget.assetId!));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? 'Asset updated' : 'Asset created')),
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
      appBar: AppBar(title: Text(_isEdit ? 'Edit Asset' : 'New Asset')),
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
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: [
                      for (final t in Asset.types)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (v) => setState(() => _type = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                    items: [
                      for (final s in Asset.statuses)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => _status = v),
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
                  const SizedBox(height: 24),
                  Text('Hardware',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _make,
                    decoration: const InputDecoration(labelText: 'Make'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _model,
                    decoration: const InputDecoration(labelText: 'Model'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _serial,
                    decoration: const InputDecoration(labelText: 'Serial'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _os,
                    decoration: const InputDecoration(labelText: 'OS'),
                  ),
                  const SizedBox(height: 24),
                  Text('Network',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _uri,
                    decoration: const InputDecoration(labelText: 'URI'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ip,
                    decoration: const InputDecoration(labelText: 'IP'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _mac,
                    decoration: const InputDecoration(labelText: 'MAC'),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _notes,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_busy
                        ? 'Saving…'
                        : _isEdit
                            ? 'Save Changes'
                            : 'Create Asset'),
                  ),
                ],
              ),
            ),
    );
  }
}

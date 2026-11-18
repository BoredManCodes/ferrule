import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_response.dart';
import '../../core/api/providers.dart';
import 'agent_banners.dart';

Color toneColor(BannerTone t) => switch (t) {
      BannerTone.danger => const Color(0xFFDC3545),
      BannerTone.warning => const Color(0xFFFFC107),
      BannerTone.info => const Color(0xFF0DCAF0),
    };

/// Banners to manage: one client's (from its page) when [clientId] is set,
/// otherwise every banner (Admin > Agent Banners, admins only).
class BannersScreen extends ConsumerStatefulWidget {
  final int? clientId;
  final String? clientName;
  const BannersScreen({super.key, this.clientId, this.clientName});

  @override
  ConsumerState<BannersScreen> createState() => _BannersScreenState();
}

class _BannersScreenState extends ConsumerState<BannersScreen> {
  bool _archived = false;

  @override
  Widget build(BuildContext context) {
    final hasWeb = ref.watch(itflowWebClientProvider) != null;
    final cid = widget.clientId;
    final title = cid != null
        ? 'Banners${widget.clientName != null ? ' · ${widget.clientName}' : ''}'
        : 'Agent Banners';

    Widget body;
    bool canAdd = false;
    if (!hasWeb) {
      body = const _Message(
          'Banners need agent email + password in Settings - ITFlow has no API for them.');
    } else if (cid != null) {
      final async = ref.watch(clientBannersProvider(cid));
      canAdd = async.value?.canEdit ?? false;
      body = async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message('Could not load banners: $e'),
        data: (st) {
          if (!st.canEdit) {
            return const _Message(
                'Your role can\'t change this client\'s banners. It takes edit access to clients.');
          }
          return _List(
            items: st.clientBanners,
            empty: 'No banners for this client. Banners that have ended or '
                'been archived are kept under Admin > Agent Banners.',
            clientId: cid,
          );
        },
      );
    } else {
      final async = ref.watch(adminBannersProvider(_archived));
      canAdd = async.value != null;
      body = async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message('Could not load banners: $e'),
        data: (items) => items == null
            ? const _Message(
                'Only admins can see every banner. Client banners are on each client\'s page.')
            : _List(
                items: items,
                empty: _archived ? 'Nothing archived.' : 'No banners.',
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => invalidateBanners(ref),
          ),
        ],
        bottom: cid == null && hasWeb
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Current')),
                      ButtonSegment(value: true, label: Text('Archived')),
                    ],
                    selected: {_archived},
                    onSelectionChanged: (s) =>
                        setState(() => _archived = s.first),
                  ),
                ),
              )
            : null,
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => context.push(
                  '/banners/new${cid != null ? '?client_id=$cid' : ''}'),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('New Banner'),
            )
          : null,
      body: body,
    );
  }
}

class _List extends ConsumerWidget {
  final List<BannerListItem> items;
  final String empty;
  final int? clientId;
  const _List({required this.items, required this.empty, this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return _Message(empty);
    return RefreshIndicator(
      onRefresh: () async => invalidateBanners(ref),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final b = items[i];
          final sub = [
            toneLabel(b.tone),
            if (b.status != null && b.status!.isNotEmpty) b.status!,
            if (b.forWho != null) b.forWho!,
            if (b.when != null && b.when!.isNotEmpty) b.when!,
          ].join(' · ');
          return ListTile(
            leading: Icon(Icons.circle, size: 14, color: toneColor(b.tone)),
            title: Text(b.title),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(
                '/banners/${b.id}${clientId != null ? '?client_id=$clientId' : ''}'),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}

/// New or existing banner, using ITFlow's own form (so the server decides
/// which clients this agent may pick and whether it's fixed to one).
class BannerFormScreen extends ConsumerStatefulWidget {
  final int? id;
  final int? clientId;
  const BannerFormScreen({super.key, this.id, this.clientId});

  @override
  ConsumerState<BannerFormScreen> createState() => _BannerFormScreenState();
}

class _BannerFormScreenState extends ConsumerState<BannerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  BannerForm? _form;
  String _tone = 'info';
  int _clientId = 0;
  DateTime? _starts;
  DateTime? _ends;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  AgentBannerRepository? get _repo => ref.read(agentBannerRepositoryProvider);

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _error = 'Banners need agent email + password in Settings.');
      return;
    }
    try {
      final f = await repo.loadForm(id: widget.id, clientId: widget.clientId);
      if (!mounted) return;
      setState(() {
        _form = f;
        _title.text = f.title;
        _body.text = f.body;
        _tone = f.tone;
        _clientId = f.clientId;
        _starts = DateTime.tryParse(f.startsAt);
        _ends = DateTime.tryParse(f.endsAt);
      });
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    }
  }

  String _msg(Object e) => e is ApiException ? e.message : '$e';

  String _fmt(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}T${two(d.hour)}:${two(d.minute)}';
  }

  Future<DateTime?> _pick(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo!.save(
        id: widget.id,
        title: _title.text.trim(),
        body: _body.text.trim(),
        tone: _tone,
        clientId: _clientId,
        startsAt: _fmt(_starts),
        endsAt: _fmt(_ends),
      );
      invalidateBanners(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.id == null ? 'Banner posted' : 'Banner saved')));
      context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(String label, Future<void> Function(int) run,
      {bool confirm = false}) async {
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete this banner?'),
          content: const Text('It goes for good.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await run(widget.id!);
      invalidateBanners(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Banner $label')));
      context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _form;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'New Banner' : 'Edit Banner'),
        actions: [
          if (f != null && widget.id != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                final repo = _repo!;
                switch (v) {
                  case 'archive':
                    _action('archived', repo.archive);
                  case 'restore':
                    _action('restored', repo.restore);
                  case 'delete':
                    _action('deleted', repo.delete, confirm: true);
                }
              },
              itemBuilder: (_) => [
                if (f.archived)
                  const PopupMenuItem(value: 'restore', child: Text('Restore'))
                else
                  const PopupMenuItem(value: 'archive', child: Text('Archive')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: f == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center))
                  : const CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _title,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'On credit hold - no work without approval',
                      prefixIcon: Icon(Icons.campaign_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _body,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 5000,
                    decoration: const InputDecoration(
                      labelText: 'Details',
                      hintText:
                          'What anyone working for them needs to know - web addresses become links',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _tone,
                    decoration: const InputDecoration(labelText: 'Shown as'),
                    items: [
                      for (final t in f.tones)
                        DropdownMenuItem(value: t.value, child: Text(t.label)),
                    ],
                    onChanged: (v) => setState(() => _tone = v ?? 'info'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      _tone == 'danger'
                          ? 'Urgent is big and red, and nobody can hide it.'
                          : 'Each agent can hide it until it is changed.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (f.clientFixed)
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'For'),
                      child: Text(_clientId == 0
                          ? 'Every client'
                          : 'This client only'),
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: f.clients.any((c) => c.id == _clientId)
                          ? _clientId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'For'),
                      items: [
                        for (final c in f.clients)
                          DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _clientId = v ?? 0),
                    ),
                  const SizedBox(height: 16),
                  _DateRow(
                    label: 'Starts',
                    empty: 'Now',
                    value: _starts,
                    onPick: () async {
                      final d = await _pick(_starts);
                      if (d != null) setState(() => _starts = d);
                    },
                    onClear: () => setState(() => _starts = null),
                  ),
                  _DateRow(
                    label: 'Ends',
                    empty: 'Until archived',
                    value: _ends,
                    onPick: () async {
                      final d = await _pick(_ends);
                      if (d != null) setState(() => _ends = d);
                    },
                    onClear: () => setState(() => _ends = null),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(widget.id == null ? 'Post Banner' : 'Save'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String empty;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _DateRow({
    required this.label,
    required this.empty,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    final text = v == null
        ? empty
        : MaterialLocalizations.of(context).formatMediumDate(v) +
            ' ' +
            MaterialLocalizations.of(context)
                .formatTimeOfDay(TimeOfDay.fromDateTime(v));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: Text(label),
      subtitle: Text(text),
      onTap: onPick,
      trailing: v == null
          ? null
          : IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.clear),
              onPressed: onClear),
    );
  }
}

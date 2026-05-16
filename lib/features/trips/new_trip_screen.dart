import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets.dart';
import 'trip_form_data.dart';
import 'trip_repository.dart';

class NewTripScreen extends ConsumerStatefulWidget {
  final TripDraft? draft;
  const NewTripScreen({super.key, this.draft});

  @override
  ConsumerState<NewTripScreen> createState() => _NewTripScreenState();
}

class _NewTripScreenState extends ConsumerState<NewTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _miles = TextEditingController();
  final _source = TextEditingController();
  final _destination = TextEditingController();
  final _purpose = TextEditingController();
  final _df = DateFormat('yyyy-MM-dd');

  DateTime _date = DateTime.now();
  bool _roundtrip = false;
  int? _driverId;
  int _clientId = 0;
  bool _busy = false;
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    if (d != null) {
      _date = d.date;
      _miles.text = d.miles.toStringAsFixed(1);
      _source.text = d.source;
      _destination.text = d.destination;
      _roundtrip = d.roundtrip;
    }
  }

  @override
  void dispose() {
    _miles.dispose();
    _source.dispose();
    _destination.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2999, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit(TripAddFormData form) async {
    if (!_formKey.currentState!.validate()) return;
    if (_driverId == null) {
      _toast('Please pick a driver');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(tripRepositoryProvider).add(
            csrfToken: form.csrfToken,
            date: _df.format(_date),
            miles: double.parse(_miles.text.trim()),
            source: _source.text.trim(),
            destination: _destination.text.trim(),
            purpose: _purpose.text.trim(),
            driverId: _driverId!,
            clientId: _clientId,
            roundtrip: _roundtrip,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip logged')),
      );
      // Pop back to /trips landing.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/trips');
      }
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tripAddFormProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New Trip')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(tripAddFormProvider),
        ),
        data: (form) {
          if (!_hydrated) {
            _driverId = form.defaultDriverId;
            _hydrated = true;
          }
          return _buildForm(form);
        },
      ),
    );
  }

  Widget _buildForm(TripAddFormData form) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date + Miles row (matches screenshot layout)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date *',
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    child: Text(_df.format(_date)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _miles,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Miles *',
                    prefixIcon: const Icon(Icons.pedal_bike_outlined),
                    hintText: '0.0',
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('R/T'),
                          Checkbox(
                            value: _roundtrip,
                            onChanged: (v) =>
                                setState(() => _roundtrip = v ?? false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final d = double.tryParse(v.trim());
                    if (d == null || d <= 0) return '> 0';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _source,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Location *',
              prefixIcon: Icon(Icons.location_on_outlined),
              hintText: 'Enter your starting location',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          TextFormField(
            controller: _destination,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Destination *',
              prefixIcon: Icon(Icons.arrow_forward),
              hintText: 'Enter destination',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _purpose,
            maxLines: 4,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Purpose *',
              alignLabelWithHint: true,
              hintText: 'Enter a purpose',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 4),
          _OptionsDropdown(
            label: 'Driver *',
            icon: Icons.person_outline,
            value: _driverId,
            options: form.drivers,
            onChanged: (v) => setState(() => _driverId = v),
          ),
          const SizedBox(height: 12),
          _OptionsDropdown(
            label: 'Client (optional)',
            icon: Icons.business_outlined,
            value: _clientId == 0 ? null : _clientId,
            options: form.clients,
            allowClear: true,
            onChanged: (v) => setState(() => _clientId = v ?? 0),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : () => _submit(form),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_busy ? 'Saving…' : 'Create'),
          ),
        ],
      ),
    );
  }
}

class _OptionsDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final int? value;
  final List<NamedOption> options;
  final ValueChanged<int?> onChanged;
  final bool allowClear;

  const _OptionsDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.allowClear = false,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
        ),
        child: Text(
          'None available',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      items: [
        if (allowClear)
          const DropdownMenuItem<int>(value: null, child: Text('— None —')),
        for (final o in options)
          DropdownMenuItem(
            value: o.id,
            child: Text(o.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

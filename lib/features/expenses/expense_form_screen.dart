import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/widgets.dart';
import '../readonly/readonly_screens.dart';
import 'expense_form_data.dart';
import 'expense_repository.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _reference = TextEditingController();
  final _df = DateFormat('yyyy-MM-dd');

  DateTime _date = DateTime.now();
  int? _accountId;
  int? _vendorId;
  int? _categoryId;
  int _clientId = 0;

  String? _receiptPath;
  List<int>? _receiptBytes;
  String? _receiptName;

  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _reference.dispose();
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

  Future<void> _pickReceiptFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    setState(() {
      _receiptPath = f.path;
      _receiptBytes = f.bytes;
      _receiptName = f.name;
    });
  }

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (shot == null) return;
      final bytes = await shot.readAsBytes();
      setState(() {
        _receiptPath = shot.path;
        _receiptBytes = bytes;
        _receiptName = shot.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera unavailable: $e')),
      );
    }
  }

  void _clearReceipt() {
    setState(() {
      _receiptPath = null;
      _receiptBytes = null;
      _receiptName = null;
    });
  }

  Future<void> _submit(ExpenseAddFormData form) async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      _toast('Please choose an account');
      return;
    }
    if (_vendorId == null) {
      _toast('Please choose a vendor');
      return;
    }
    if (_categoryId == null) {
      _toast('Please choose a category');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(expenseRepositoryProvider).add(
            csrfToken: form.csrfToken,
            date: _df.format(_date),
            amount: double.parse(_amount.text.trim()),
            accountId: _accountId!,
            vendorId: _vendorId!,
            categoryId: _categoryId!,
            clientId: _clientId,
            description: _description.text.trim(),
            reference: _reference.text.trim(),
            receiptFilePath: _receiptPath,
            receiptBytes: _receiptBytes,
            receiptFileName: _receiptName,
          );
      if (!mounted) return;
      invalidateModuleList(ref, 'expenses');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense added')),
      );
      context.pop();
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
    final async = ref.watch(expenseAddFormProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New Expense')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(expenseAddFormProvider),
        ),
        data: (form) {
          // Hydrate default account once when the form data first loads.
          if (_accountId == null && form.defaultAccountId != null) {
            _accountId = form.defaultAccountId;
          }
          return _buildForm(form);
        },
      ),
    );
  }

  Widget _buildForm(ExpenseAddFormData form) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date *',
                prefixIcon: Icon(Icons.calendar_month_outlined),
              ),
              child: Text(_df.format(_date)),
            ),
          ),
          const SizedBox(height: 12),
          // Amount
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Amount *',
              prefixIcon: Icon(Icons.attach_money),
              hintText: '0.00',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final d = double.tryParse(v.trim());
              if (d == null || d <= 0) return 'Enter a number > 0';
              return null;
            },
          ),
          const SizedBox(height: 12),
          // Account
          _OptionsDropdown(
            label: 'Account *',
            icon: Icons.account_balance_outlined,
            value: _accountId,
            options: form.accounts,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 12),
          // Vendor
          _OptionsDropdown(
            label: 'Vendor *',
            icon: Icons.store_outlined,
            value: _vendorId,
            options: form.vendors,
            onChanged: (v) => setState(() => _vendorId = v),
          ),
          const SizedBox(height: 12),
          // Description
          TextFormField(
            controller: _description,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Description *',
              alignLabelWithHint: true,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          // Reference
          TextFormField(
            controller: _reference,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Reference',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 4),
          // Category
          _OptionsDropdown(
            label: 'Category *',
            icon: Icons.label_outline,
            value: _categoryId,
            options: form.categories,
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          // Client (optional)
          _OptionsDropdown(
            label: 'Client (optional)',
            icon: Icons.business_outlined,
            value: _clientId == 0 ? null : _clientId,
            options: form.clients,
            allowClear: true,
            onChanged: (v) => setState(() => _clientId = v ?? 0),
          ),
          const SizedBox(height: 20),
          _ReceiptSection(
            name: _receiptName,
            bytes: _receiptBytes,
            path: _receiptPath,
            onTakePhoto: _takePhoto,
            onPickFile: _pickReceiptFile,
            onClear: _clearReceipt,
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

class _ReceiptSection extends StatelessWidget {
  final String? name;
  final List<int>? bytes;
  final String? path;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickFile;
  final VoidCallback onClear;

  const _ReceiptSection({
    required this.name,
    required this.bytes,
    required this.path,
    required this.onTakePhoto,
    required this.onPickFile,
    required this.onClear,
  });

  bool get _isImage {
    final n = name?.toLowerCase() ?? '';
    return n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined,
                    color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('Receipt',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (name != null)
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Remove'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (name != null) ...[
              if (_isImage) _ImagePreview(path: path, bytes: bytes),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  name!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Image or PDF — optional. ITFlow accepts jpg, jpeg, png, gif, webp, pdf.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTakePhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickFile,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Choose file'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final String? path;
  final List<int>? bytes;
  const _ImagePreview({required this.path, required this.bytes});

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (bytes != null && bytes!.isNotEmpty) {
      child = Image.memory(
        Uint8List.fromList(bytes!),
        fit: BoxFit.cover,
        height: 160,
        width: double.infinity,
      );
    } else if (path != null) {
      child = Image.file(
        File(path!),
        fit: BoxFit.cover,
        height: 160,
        width: double.infinity,
      );
    } else {
      return const SizedBox.shrink();
    }
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: child);
  }
}

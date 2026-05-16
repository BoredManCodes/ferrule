import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets.dart';
import '../expenses/expense_form_data.dart';
import '../readonly/readonly_screens.dart';
import 'payment_form_data.dart';
import 'payment_repository.dart';

class PaymentFormScreen extends ConsumerWidget {
  final int invoiceId;
  const PaymentFormScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(paymentAddFormProvider(invoiceId));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.value == null
            ? 'Make Payment'
            : '${async.value!.invoiceLabel}: Make Payment'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(paymentAddFormProvider(invoiceId)),
        ),
        data: (form) => _PaymentFormBody(form: form),
      ),
    );
  }
}

class _PaymentFormBody extends ConsumerStatefulWidget {
  final PaymentAddFormData form;
  const _PaymentFormBody({required this.form});

  @override
  ConsumerState<_PaymentFormBody> createState() => _PaymentFormBodyState();
}

class _PaymentFormBodyState extends ConsumerState<_PaymentFormBody> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _df = DateFormat('yyyy-MM-dd');

  late DateTime _date;
  int? _accountId;
  String? _paymentMethod;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _amount.text = widget.form.balance.toStringAsFixed(2);
    _accountId = widget.form.defaultAccountId;
    _paymentMethod = widget.form.defaultPaymentMethod;
  }

  @override
  void dispose() {
    _amount.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      _toast('Please choose an account');
      return;
    }
    if (_paymentMethod == null) {
      _toast('Please choose a payment method');
      return;
    }
    final amount = double.parse(_amount.text.trim());
    if (amount > widget.form.balance + 0.0001) {
      _toast(
          'Amount can\'t exceed the balance (${widget.form.balance.toStringAsFixed(2)} ${widget.form.currencyCode}).');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(paymentRepositoryProvider).add(
            csrfToken: widget.form.csrfToken,
            invoiceId: widget.form.invoiceId,
            balance: widget.form.balance,
            currencyCode: widget.form.currencyCode,
            date: _df.format(_date),
            amount: amount,
            accountId: _accountId!,
            paymentMethod: _paymentMethod!,
            reference: _reference.text.trim(),
          );
      if (!mounted) return;
      // Invalidate cached invoice + list so the new status (Paid / Partial)
      // and balance reflect on the previous screen.
      invalidateModuleList(ref, 'invoices');
      ref.invalidate(paymentAddFormProvider(widget.form.invoiceId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded')),
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
    final balanceFmt = NumberFormat.currency(
      name: widget.form.currencyCode,
      symbol: '',
    ).format(widget.form.balance);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Balance',
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          '$balanceFmt ${widget.form.currencyCode}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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
          _AccountDropdown(
            value: _accountId,
            options: widget.form.accounts,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 12),
          _PaymentMethodDropdown(
            value: _paymentMethod,
            options: widget.form.paymentMethods,
            onChanged: (v) => setState(() => _paymentMethod = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reference,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Reference',
              prefixIcon: Icon(Icons.tag),
              hintText: 'Check #, Trans #, etc',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_busy ? 'Saving…' : 'Pay'),
          ),
        ],
      ),
    );
  }
}

class _AccountDropdown extends StatelessWidget {
  final int? value;
  final List<NamedOption> options;
  final ValueChanged<int?> onChanged;
  const _AccountDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Account *',
          prefixIcon: Icon(Icons.account_balance_outlined),
        ),
        child: Text('No accounts available'),
      );
    }
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Account *',
        prefixIcon: Icon(Icons.account_balance_outlined),
      ),
      items: [
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

class _PaymentMethodDropdown extends StatelessWidget {
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  const _PaymentMethodDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Payment Method *',
          prefixIcon: Icon(Icons.payments_outlined),
        ),
        child: Text('No payment methods configured'),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Payment Method *',
        prefixIcon: Icon(Icons.payments_outlined),
      ),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: onChanged,
    );
  }
}

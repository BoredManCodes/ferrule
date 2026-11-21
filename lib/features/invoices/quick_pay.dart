import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_response.dart';
import '../../core/api/itflow_client.dart';
import '../../core/api/providers.dart';
import '../../core/util.dart';
import '../readonly/readonly_screens.dart';
import 'cash_tender.dart';

const quickPayScope = 'On-site payment, details to follow';
const quickPayLineName = 'On-site service';

/// A step of the quick-pay chain went wrong. [invoiceId] is set once the
/// invoice exists, so the tech can open it and finish by hand.
class QuickPayException implements Exception {
  final String step;
  final int? invoiceId;
  final String message;
  QuickPayException(this.step, this.invoiceId, this.message);
  @override
  String toString() => 'Step failed: $step. $message';
}

class QuickPayResult {
  final int invoiceId;
  final double total;

  /// Something that didn't stop the payment but the tech should know.
  final String? warning;
  const QuickPayResult(this.invoiceId, this.total, {this.warning});
}

class QuickPayRepository {
  final Ref ref;
  QuickPayRepository(this.ref);

  /// Makes a sent invoice for [amount] (tax included, at the client's usual
  /// rate) ready to take payment on, linked to [ticketId] when given.
  Future<QuickPayResult> create({
    required int clientId,
    int? ticketId,
    required double amount,
    required String lineName,
    String note = '',
  }) async {
    final web = requireWebClient(ref);
    final api = requireClient(ref);
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int? invoiceId;

    Future<T> step<T>(String name, Future<T> Function() run) async {
      try {
        return await run();
      } catch (e) {
        final msg = e is Exception
            ? e.toString().replaceFirst(
                RegExp(r'^\w*Exception(\(\w*\))?: '),
                '',
              )
            : '$e';
        throw QuickPayException(name, invoiceId, msg);
      }
    }

    final id = await step(
      'create invoice',
      () => web.createInvoice(
        clientId: clientId,
        scope: quickPayScope,
        date: date,
      ),
    );
    invoiceId = id;

    // A non-billable or already invoiced ticket can't go on; take the
    // money anyway and say so.
    String? warning;
    if (ticketId != null) {
      try {
        await web.linkTicketToInvoice(invoiceId: id, ticketId: ticketId);
      } on ApiException catch (e) {
        // Upstream only links tickets that are resolved or closed and
        // billable; an open one gets refused.
        warning =
            'Ticket not put on the invoice (${e.message}) Add it from '
            'the web once the ticket is resolved.';
      }
    }

    final itemId = await step(
      'add line',
      () => web.addInvoiceLine(
        invoiceId: id,
        name: lineName,
        description: note,
        price: amount,
      ),
    );

    // The line got the client's usual tax on top of the amount. Bring the
    // price down so the line, tax and all, comes to what was typed.
    await step('set tax-inclusive price', () async {
      final item = await _item(api, id, itemId);
      final subtotal = toDouble(item?['item_subtotal']) ?? amount;
      final tax = toDouble(item?['item_tax']) ?? 0;
      if (tax <= 0 || subtotal <= 0) return;
      final price = priceForGross(amount, tax / subtotal);
      if (price == null) return;
      await web.setInvoiceLineField(
        invoiceId: id,
        itemId: itemId,
        field: 'price',
        value: price.toStringAsFixed(2),
      );
    });

    await step('mark sent', () => web.markInvoiceSent(id));

    final total = await step('read total', () async {
      final r = await api.get('invoices', 'read', query: {'invoice_id': id});
      return toDouble(r.row?['invoice_amount']) ?? amount;
    });
    return QuickPayResult(id, total, warning: warning);
  }

  Future<Map<String, dynamic>?> _item(
    ItflowClient api,
    int invoiceId,
    int itemId,
  ) async {
    final r = await api.get(
      'invoice_items',
      'read',
      query: {'invoice_id': invoiceId, 'limit': 200},
    );
    for (final row in r.rows) {
      if (toInt(row['item_id']) == itemId) return row;
    }
    return null;
  }
}

final quickPayRepositoryProvider = Provider<QuickPayRepository>(
  (ref) => QuickPayRepository(ref),
);

enum _Then { cash, card, other }

/// Take money on site now; the invoice gets tidied up in the office.
class QuickPayScreen extends ConsumerStatefulWidget {
  final int clientId;
  final int? ticketId;
  final String? defaultLineName;
  const QuickPayScreen({
    super.key,
    required this.clientId,
    this.ticketId,
    this.defaultLineName,
  });

  @override
  ConsumerState<QuickPayScreen> createState() => _QuickPayScreenState();
}

class _QuickPayScreenState extends ConsumerState<QuickPayScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late final _line = TextEditingController(
    text: widget.defaultLineName ?? quickPayLineName,
  );
  final _note = TextEditingController();
  _Then? _busy;

  @override
  void dispose() {
    _amount.dispose();
    _line.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _go(_Then then) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = then);
    try {
      final r = await ref
          .read(quickPayRepositoryProvider)
          .create(
            clientId: widget.clientId,
            ticketId: widget.ticketId,
            amount: double.parse(_amount.text.replaceAll(',', '').trim()),
            lineName: _line.text.trim(),
            note: _note.text.trim(),
          );
      if (!mounted) return;
      invalidateModuleList(ref, 'invoices');
      if (r.warning != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(r.warning!),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      final path = switch (then) {
        _Then.cash => '/invoices/${r.invoiceId}/pay?method=Cash&quick=1',
        _Then.card => '/invoices/${r.invoiceId}/qr?quick=1',
        _Then.other => '/invoices/${r.invoiceId}/pay?quick=1',
      };
      context.pushReplacement(path);
    } on QuickPayException catch (e) {
      if (!mounted) return;
      final id = e.invoiceId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          duration: const Duration(seconds: 8),
          action: id == null
              ? null
              : SnackBarAction(
                  label: 'Open invoice',
                  onPressed: () => context.pushReplacement('/invoices/$id'),
                ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _button(
    _Then then,
    IconData icon,
    String label, {
    bool filled = false,
  }) {
    final busy = _busy == then;
    final onPressed = _busy != null ? null : () => _go(then);
    final iconW = busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon);
    return filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: iconW,
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: iconW,
            label: Text(label),
          );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick payment')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Makes an invoice for this amount, GST included at the '
              "client's usual rate, and marks it sent. Fix the scope and "
              'dates in the office; the line locks once paid.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount, tax included *',
                prefixIcon: Icon(Icons.attach_money),
                hintText: '0.00',
              ),
              validator: (v) {
                final d = double.tryParse((v ?? '').replaceAll(',', '').trim());
                if (d == null || d <= 0) return 'Enter a number > 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _line,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Line *',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Line description',
                prefixIcon: Icon(Icons.notes_outlined),
                hintText: 'What was done, shown under the line',
              ),
            ),
            const SizedBox(height: 20),
            _button(
              _Then.cash,
              Icons.payments_outlined,
              'Take cash',
              filled: true,
            ),
            const SizedBox(height: 8),
            _button(_Then.card, Icons.qr_code_2, 'Card on their phone (QR)'),
            const SizedBox(height: 8),
            _button(
              _Then.other,
              Icons.point_of_sale_outlined,
              'Other method (EFTPOS etc.)',
            ),
          ],
        ),
      ),
    );
  }
}

/// Leaving a quick-pay invoice's payment or QR screen. If nothing was paid,
/// offer to cancel it so it isn't left owing (and later overdue). True when
/// the screen may close.
Future<bool> confirmQuickPayExit(
  BuildContext context,
  WidgetRef ref,
  int invoiceId,
) async {
  final api = ref.read(itflowClientProvider);
  final web = ref.read(itflowWebClientProvider);
  if (api == null || web == null) return true;
  Map<String, dynamic>? row;
  try {
    row = (await api.get(
      'invoices',
      'read',
      query: {'invoice_id': invoiceId},
    )).row;
  } catch (_) {
    return true; // can't tell; don't trap the tech on the screen
  }
  final status = (str(row?['invoice_status']) ?? '').toLowerCase();
  if (row == null || const ['paid', 'partial', 'cancelled'].contains(status)) {
    return true;
  }
  if (!context.mounted) return true;
  final label =
      '${str(row['invoice_prefix']) ?? ''}${str(row['invoice_number']) ?? ''}';
  final amount = (toDouble(row['invoice_amount']) ?? 0).toStringAsFixed(2);
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Not paid yet'),
      content: Text(
        "$label is still owing $amount. If the customer isn't "
        "paying, cancel it so it doesn't go overdue.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, 'stay'),
          child: const Text('Stay'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, 'keep'),
          child: const Text('Keep owing'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, 'cancel'),
          child: const Text('Cancel invoice'),
        ),
      ],
    ),
  );
  if (choice == null || choice == 'stay') return false;
  if (choice == 'keep') return true;
  if (!context.mounted) return true;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await web.cancelInvoice(invoiceId);
    final after = (await api.get(
      'invoices',
      'read',
      query: {'invoice_id': invoiceId},
    )).row;
    final ok =
        (str(after?['invoice_status']) ?? '').toLowerCase() == 'cancelled';
    invalidateModuleList(ref, 'invoices');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '$label cancelled'
              : 'ITFlow did not cancel $label. Cancel it on the web.',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not cancel $label: $e')),
    );
  }
  return true;
}

/// Guards a quick-pay screen: leaving asks [confirmQuickPayExit] first.
class QuickPayExitGuard extends ConsumerStatefulWidget {
  final int invoiceId;
  final bool enabled;
  final Widget child;
  const QuickPayExitGuard({
    super.key,
    required this.invoiceId,
    required this.enabled,
    required this.child,
  });

  /// Lets the screen close without asking (it just recorded a payment).
  static void release(BuildContext context) =>
      context.findAncestorStateOfType<_QuickPayExitGuardState>()?._released =
          true;

  /// Asks if needed, then closes the screen.
  static Future<void> leave(BuildContext context) async =>
      context.findAncestorStateOfType<_QuickPayExitGuardState>()?._tryLeave();

  @override
  ConsumerState<QuickPayExitGuard> createState() => _QuickPayExitGuardState();
}

class _QuickPayExitGuardState extends ConsumerState<QuickPayExitGuard> {
  bool _released = false;
  bool _asking = false;

  Future<void> _tryLeave() async {
    if (_asking) return;
    if (!widget.enabled || _released) {
      if (mounted) context.pop();
      return;
    }
    _asking = true;
    final ok = await confirmQuickPayExit(context, ref, widget.invoiceId);
    _asking = false;
    if (ok && mounted) {
      setState(() => _released = true);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.enabled || _released,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _tryLeave();
    },
    child: widget.child,
  );
}

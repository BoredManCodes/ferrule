import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/api/providers.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../readonly/readonly_screens.dart';

/// The invoice row from the API, read fresh each time the screen opens.
final payQrInvoiceProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, int>((ref, id) async {
  await ref.watch(credentialsProvider.future);
  final r = await requireClient(ref)
      .get('invoices', 'read', query: {'invoice_id': id});
  return r.success ? r.row : null;
});

/// Guest pay link for an invoice, or null without a key or instance.
String? guestInvoiceUrl(String? instanceUrl, int invoiceId, String? urlKey) {
  if (instanceUrl == null || instanceUrl.isEmpty) return null;
  if (urlKey == null || urlKey.isEmpty) return null;
  final root = instanceUrl.endsWith('/')
      ? instanceUrl.substring(0, instanceUrl.length - 1)
      : instanceUrl;
  return '$root/guest/guest_view_invoice.php?invoice_id=$invoiceId&url_key=$urlKey';
}

/// Full-screen QR the customer scans to pay the invoice on their own phone.
class PayQrScreen extends ConsumerStatefulWidget {
  final int invoiceId;
  const PayQrScreen({super.key, required this.invoiceId});

  @override
  ConsumerState<PayQrScreen> createState() => _PayQrScreenState();
}

class _PayQrScreenState extends ConsumerState<PayQrScreen> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  void _done() {
    invalidateModuleList(ref, 'invoices');
    ref.invalidate(payQrInvoiceProvider(widget.invoiceId));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(payQrInvoiceProvider(widget.invoiceId));
    final instance = ref.watch(credentialsProvider).value?.instanceUrl;
    return Scaffold(
      appBar: AppBar(title: const Text('Pay by phone')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(payQrInvoiceProvider(widget.invoiceId)),
        ),
        data: (r) {
          if (r == null) {
            return const Center(child: Text('Invoice not found.'));
          }
          final url = guestInvoiceUrl(
              instance, widget.invoiceId, str(r['invoice_url_key']));
          if (url == null) {
            return const Center(
                child: Text('This invoice has no guest link to share.'));
          }
          final status = str(r['invoice_status']) ?? '';
          final cur = str(r['invoice_currency_code']) ?? '';
          final total = NumberFormat.currency(name: cur, symbol: '')
              .format(toDouble(r['invoice_amount']) ?? 0);
          final label =
              '${str(r['invoice_prefix']) ?? ''}${str(r['invoice_number']) ?? ''}';
          final theme = Theme.of(context);
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('$label  ·  $status',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('$total $cur',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: QrImageView(
                      data: url,
                      size: 280,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Customer scans to open the invoice and pay by card. '
                  'No Pay button on their screen means no card provider is '
                  'set up in ITFlow.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _done,
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

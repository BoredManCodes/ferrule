import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import 'payment_form_data.dart';

class PaymentRepository {
  final Ref ref;
  PaymentRepository(this.ref);

  Future<PaymentAddFormData> fetchAddForm(int invoiceId) async {
    final web = requireWebClient(ref);
    return web.fetchInvoicePaymentForm(invoiceId);
  }

  Future<void> add({
    required String csrfToken,
    required int invoiceId,
    required double balance,
    required String currencyCode,
    required String date,
    required double amount,
    required int accountId,
    required String paymentMethod,
    String reference = '',
    bool emailReceipt = false,
  }) async {
    final web = requireWebClient(ref);
    await web.addInvoicePayment(
      csrfToken: csrfToken,
      invoiceId: invoiceId,
      balance: balance,
      currencyCode: currencyCode,
      date: date,
      amount: amount,
      accountId: accountId,
      paymentMethod: paymentMethod,
      reference: reference,
      emailReceipt: emailReceipt,
    );
  }
}

final paymentRepositoryProvider =
    Provider<PaymentRepository>((ref) => PaymentRepository(ref));

final paymentAddFormProvider = FutureProvider.autoDispose
    .family<PaymentAddFormData, int>((ref, invoiceId) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(paymentRepositoryProvider).fetchAddForm(invoiceId);
});

import '../expenses/expense_form_data.dart';

/// Everything needed to render and submit the "Make Payment" modal for an
/// invoice. [accounts] are id-based NamedOptions (server expects account_id),
/// while [paymentMethods] are bare strings because the upstream <select>
/// posts the option's text content (no `value` attribute).
class PaymentAddFormData {
  final String csrfToken;
  final int invoiceId;
  final String invoiceLabel;
  final double balance;
  final String currencyCode;
  final List<NamedOption> accounts;
  final List<String> paymentMethods;
  final int? defaultAccountId;
  final String? defaultPaymentMethod;

  const PaymentAddFormData({
    required this.csrfToken,
    required this.invoiceId,
    required this.invoiceLabel,
    required this.balance,
    required this.currencyCode,
    required this.accounts,
    required this.paymentMethods,
    this.defaultAccountId,
    this.defaultPaymentMethod,
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import 'expense_form_data.dart';

class ExpenseRepository {
  final Ref ref;
  ExpenseRepository(this.ref);

  Future<ExpenseAddFormData> fetchAddForm() async {
    final web = requireWebClient(ref);
    return web.fetchExpenseAddForm();
  }

  Future<void> add({
    required String csrfToken,
    required String date,
    required double amount,
    required int accountId,
    required int vendorId,
    required int categoryId,
    required int clientId,
    required String description,
    required String reference,
    String? receiptFilePath,
    List<int>? receiptBytes,
    String? receiptFileName,
  }) async {
    final web = requireWebClient(ref);
    await web.addExpense(
      csrfToken: csrfToken,
      date: date,
      amount: amount,
      accountId: accountId,
      vendorId: vendorId,
      categoryId: categoryId,
      clientId: clientId,
      description: description,
      reference: reference,
      receiptFilePath: receiptFilePath,
      receiptBytes: receiptBytes,
      receiptFileName: receiptFileName,
    );
  }
}

final expenseRepositoryProvider =
    Provider<ExpenseRepository>((ref) => ExpenseRepository(ref));

final expenseAddFormProvider =
    FutureProvider.autoDispose<ExpenseAddFormData>((ref) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(expenseRepositoryProvider).fetchAddForm();
});

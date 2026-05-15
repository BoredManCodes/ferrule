class NamedOption {
  final int id;
  final String name;
  const NamedOption({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      other is NamedOption && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

class ExpenseAddFormData {
  final String csrfToken;
  final List<NamedOption> accounts;
  final List<NamedOption> vendors;
  final List<NamedOption> categories;
  final List<NamedOption> clients;
  final int? defaultAccountId;

  const ExpenseAddFormData({
    required this.csrfToken,
    required this.accounts,
    required this.vendors,
    required this.categories,
    required this.clients,
    this.defaultAccountId,
  });
}

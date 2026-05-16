import '../expenses/expense_form_data.dart' show NamedOption;

export '../expenses/expense_form_data.dart' show NamedOption;

class TripAddFormData {
  final String csrfToken;
  final List<NamedOption> drivers;
  final List<NamedOption> clients;
  final int? defaultDriverId;

  const TripAddFormData({
    required this.csrfToken,
    required this.drivers,
    required this.clients,
    this.defaultDriverId,
  });
}

/// Result of a finished GPS trip — what gets pre-filled into the review form
/// before the user adds purpose / client / driver and confirms.
class TripDraft {
  final DateTime date;
  final double miles;
  final String source;
  final String destination;
  final bool roundtrip;

  const TripDraft({
    required this.date,
    required this.miles,
    required this.source,
    required this.destination,
    this.roundtrip = false,
  });
}

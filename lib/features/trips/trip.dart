/// A trip row as displayed on `/agent/trips.php`. The web list is the source
/// of truth (ITFlow's REST API has no trips endpoint), so this model only
/// carries what the table renders.
class Trip {
  final int id;
  final String date;
  final String driver;
  final String purpose;
  final String source;
  final String destination;
  final double miles;
  final bool roundtrip;
  final String? clientName;

  const Trip({
    required this.id,
    required this.date,
    required this.driver,
    required this.purpose,
    required this.source,
    required this.destination,
    required this.miles,
    required this.roundtrip,
    this.clientName,
  });
}

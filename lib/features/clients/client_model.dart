import '../../core/util.dart';

class Client {
  final int id;
  final String? name;
  final String? type;
  final String? website;
  final String? phone;
  final String? email;
  final String? notes;
  final DateTime? archivedAt;
  final Map<String, dynamic> raw;

  Client({
    required this.id,
    this.name,
    this.type,
    this.website,
    this.phone,
    this.email,
    this.notes,
    this.archivedAt,
    this.raw = const {},
  });

  bool get archived => archivedAt != null;

  factory Client.fromRow(Map<String, dynamic> r) => Client(
        id: toInt(r['client_id']) ?? 0,
        name: str(r['client_name']),
        type: str(r['client_type']),
        website: str(r['client_website']),
        phone: str(r['client_phone']),
        email: str(r['client_email']),
        notes: str(r['client_notes']),
        archivedAt: toDate(r['client_archived_at']),
        raw: r,
      );
}

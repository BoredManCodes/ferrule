import '../../core/util.dart';

class Contact {
  final int id;
  final String? name;
  final String? title;
  final String? email;
  final String? phone;
  final String? mobile;
  final String? department;
  final bool primary;
  final int? clientId;
  final DateTime? archivedAt;
  final Map<String, dynamic> raw;

  Contact({
    required this.id,
    this.name,
    this.title,
    this.email,
    this.phone,
    this.mobile,
    this.department,
    this.primary = false,
    this.clientId,
    this.archivedAt,
    this.raw = const {},
  });

  bool get archived => archivedAt != null;

  factory Contact.fromRow(Map<String, dynamic> r) => Contact(
        id: toInt(r['contact_id']) ?? 0,
        name: str(r['contact_name']),
        title: str(r['contact_title']),
        email: str(r['contact_email']),
        phone: str(r['contact_phone']),
        mobile: str(r['contact_mobile']),
        department: str(r['contact_department']),
        primary: toBool(r['contact_primary']),
        clientId: toInt(r['contact_client_id']),
        archivedAt: toDate(r['contact_archived_at']),
        raw: r,
      );
}

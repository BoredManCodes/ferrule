import '../../core/util.dart';

class Contact {
  final int id;
  final String? name;
  final String? title;
  final String? email;
  final String? phone;
  final String? mobile;
  final String? department;
  final String? notes;
  final bool primary;
  final bool important;
  final bool billing;
  final bool technical;
  final int? clientId;
  final int? vendorId;
  final int? locationId;
  final DateTime? createdAt;
  final DateTime? accessedAt;
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
    this.notes,
    this.primary = false,
    this.important = false,
    this.billing = false,
    this.technical = false,
    this.clientId,
    this.vendorId,
    this.locationId,
    this.createdAt,
    this.accessedAt,
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
        notes: str(r['contact_notes']),
        primary: toBool(r['contact_primary']),
        important: toBool(r['contact_important']),
        billing: toBool(r['contact_billing']),
        technical: toBool(r['contact_technical']),
        clientId: toInt(r['contact_client_id']),
        vendorId: toInt(r['contact_vendor_id']),
        locationId: toInt(r['contact_location_id']),
        createdAt: toDate(r['contact_created_at']),
        accessedAt: toDate(r['contact_accessed_at']),
        archivedAt: toDate(r['contact_archived_at']),
        raw: r,
      );
}

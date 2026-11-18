import '../../core/util.dart';

class Ticket {
  final int id;
  final String? prefix;
  final int? number;
  final String? subject;
  final String? details;
  final String? priority;
  final int? statusId;
  final String? statusName;
  final int? clientId;
  final int? contactId;
  final int? assetId;
  final int? assignedTo;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final String? source;
  final bool billable;
  final Map<String, dynamic> raw;

  Ticket({
    required this.id,
    this.prefix,
    this.number,
    this.subject,
    this.details,
    this.priority,
    this.statusId,
    this.statusName,
    this.clientId,
    this.contactId,
    this.assetId,
    this.assignedTo,
    this.createdAt,
    this.resolvedAt,
    this.closedAt,
    this.source,
    this.billable = false,
    this.raw = const {},
  });

  String get displayNumber {
    final p = prefix ?? '';
    final n = number?.toString() ?? id.toString();
    return '$p$n';
  }

  /// Built-in ITFlow statuses: 1 New, 2 Open, 3 On Hold, 4 Resolved,
  /// 5 Closed. Custom statuses get higher ids.
  bool get isResolved =>
      resolvedAt != null ||
      closedAt != null ||
      statusId == 4 ||
      statusId == 5 ||
      const {'resolved', 'closed'}.contains(statusName?.toLowerCase());

  bool get isClosed => closedAt != null || statusId == 5;

  factory Ticket.fromRow(Map<String, dynamic> r) => Ticket(
        id: toInt(r['ticket_id']) ?? 0,
        prefix: str(r['ticket_prefix']),
        number: toInt(r['ticket_number']),
        subject: str(r['ticket_subject']),
        details: str(r['ticket_details']),
        priority: str(r['ticket_priority']),
        statusId: toInt(r['ticket_status']),
        statusName: str(r['ticket_status_name']),
        clientId: toInt(r['ticket_client_id']),
        contactId: toInt(r['ticket_contact_id']),
        assetId: toInt(r['ticket_asset_id']),
        assignedTo: toInt(r['ticket_assigned_to']),
        createdAt: toDate(r['ticket_created_at']),
        resolvedAt: toDate(r['ticket_resolved_at']),
        closedAt: toDate(r['ticket_closed_at']),
        source: str(r['ticket_source']),
        billable: toBool(r['ticket_billable']),
        raw: r,
      );
}

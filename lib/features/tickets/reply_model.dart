import 'package:intl/intl.dart';

enum ReplyType { internal, public, client }

class TicketReply {
  final int id;
  final String authorName;
  final String? authorInitials;
  final ReplyType type;
  final String bodyHtml;
  final String? timeWorked; // "00:01:30" or null/empty if none
  final String? createdAgo; // "9 seconds ago"
  final String? createdAtRaw; // ISO-ish from title attr if scrapeable

  TicketReply({
    required this.id,
    required this.authorName,
    this.authorInitials,
    required this.type,
    required this.bodyHtml,
    this.timeWorked,
    this.createdAgo,
    this.createdAtRaw,
  });

  bool get hasTimeWorked =>
      timeWorked != null &&
      timeWorked!.isNotEmpty &&
      timeWorked != '00:00:00';
}

/// Builds a reply from an `api/v1/ticket_replies/read` row.
TicketReply ticketReplyFromApi(Map<String, dynamic> r) {
  final typeRaw = (r['ticket_reply_type'] ?? '').toString().toLowerCase();
  final type = switch (typeRaw) {
    'internal' => ReplyType.internal,
    'client' => ReplyType.client,
    _ => ReplyType.public,
  };
  var name = (r['ticket_reply_by_name'] ?? '').toString().trim();
  if (name.isEmpty) name = type == ReplyType.client ? 'Client' : 'Agent';
  final initials = name
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .take(2)
      .map((p) => p[0].toUpperCase())
      .join();
  final createdRaw = r['ticket_reply_created_at']?.toString();
  final created = createdRaw == null ? null : DateTime.tryParse(createdRaw);
  return TicketReply(
    id: int.tryParse('${r['ticket_reply_id']}') ?? 0,
    authorName: name,
    authorInitials: initials,
    type: type,
    bodyHtml: (r['ticket_reply'] ?? '').toString(),
    timeWorked: r['ticket_reply_time_worked']?.toString(),
    // The server's wall clock, as ITFlow shows it; a relative "x ago" would
    // be off by the gap between the server's and the phone's time zones.
    createdAgo: created == null
        ? createdRaw
        : DateFormat('MMM d, h:mm a').format(created),
    createdAtRaw: createdRaw,
  );
}

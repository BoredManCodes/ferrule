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

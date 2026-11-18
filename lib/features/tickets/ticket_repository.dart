import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_response.dart';
import '../../core/api/providers.dart';
import '../../core/util.dart';
import 'reply_model.dart';
import 'ticket_model.dart';

class TicketRepository {
  final Ref ref;
  TicketRepository(this.ref);

  /// Fetches every ticket by walking pages.
  ///
  /// ITFlow's v1 API only supports `LIMIT`/`OFFSET` with `ORDER BY ticket_id ASC`
  /// — there's no DESC sort, no count, and no status filter. So we page forward
  /// in [pageSize] chunks until a short page arrives, then sort client-side.
  /// Hard-capped at [maxTickets] to avoid runaway loads.
  Future<List<Ticket>> listAll({
    int pageSize = 500,
    int maxTickets = 20000,
    void Function(int loaded)? onProgress,
  }) async {
    final client = requireClient(ref);
    final all = <Ticket>[];
    var offset = 0;
    while (offset < maxTickets) {
      final resp = await client.get('tickets', 'read', query: {
        'limit': pageSize,
        'offset': offset,
      });
      if (!resp.success) break;
      final rows = resp.rows;
      if (rows.isEmpty) break;
      all.addAll(rows.map(Ticket.fromRow));
      onProgress?.call(all.length);
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  }

  Future<Ticket?> get(int id) async {
    final client = requireClient(ref);
    final resp =
        await client.get('tickets', 'read', query: {'ticket_id': id});
    if (!resp.success || resp.row == null) return null;
    return Ticket.fromRow(resp.row!);
  }

  Future<({int? id, String? error})> create({
    required String subject,
    String? details,
    String priority = 'Medium',
    int contactId = 0,
    int assetId = 0,
    int assignedTo = 0,
    int vendorId = 0,
    String? vendorTicketNumber,
    bool billable = false,
    int clientId = 0,
  }) async {
    final client = requireClient(ref);
    final resp = await client.post('tickets', 'create', body: {
      if (clientId > 0) 'client_id': clientId,
      'ticket_subject': subject,
      'ticket_details': details ?? '',
      'ticket_priority': priority,
      'ticket_contact_id': contactId,
      'ticket_asset_id': assetId,
      'ticket_assigned_to': assignedTo,
      'ticket_vendor_id': vendorId,
      'ticket_vendor_ticket_id': vendorTicketNumber ?? '',
      'ticket_billable': billable ? 1 : 0,
    });
    if (!resp.success) return (id: null, error: resp.message);
    return (id: resp.insertId, error: null);
  }

  /// Resolves a ticket. [clientId] is the ticket's client: an API key that
  /// can reach every client only matches the ticket when it's sent.
  Future<({bool ok, String? error})> resolve(int ticketId,
      {int clientId = 0}) async {
    final client = requireClient(ref);
    try {
      final resp = await client.post('tickets', 'resolve', body: {
        'ticket_id': ticketId,
        if (clientId > 0) 'client_id': clientId,
      });
      return (ok: resp.success, error: resp.success ? null : resp.message);
    } on ApiException catch (e) {
      return (ok: false, error: e.message);
    }
  }

  /// Posts a reply via the REST API (`ticket_replies/create`). Works without
  /// agent web credentials. The API knows two kinds: Internal (0) and Public,
  /// which always emails the contact and watchers (2). A public note that
  /// isn't emailed (1) has no API equivalent, so it needs the web client
  /// ([ItflowWebClient.addTicketReply]).
  ///
  /// [status] 0 leaves the ticket status alone.
  Future<({bool ok, String? error})> addReply({
    required int ticketId,
    required String body,
    int replyType = 0,
    int status = 0,
    int clientId = 0,
    Duration timeWorked = Duration.zero,
  }) async {
    if (replyType == 1) {
      return (
        ok: false,
        error:
            'Public notes without an email need agent email + password in Settings.'
      );
    }
    final client = requireClient(ref);
    String two(int n) => n.toString().padLeft(2, '0');
    try {
      final resp = await client.post('ticket_replies', 'create', body: {
        'ticket_id': ticketId,
        if (clientId > 0) 'client_id': clientId,
        'ticket_reply': body,
        'ticket_reply_type': replyType == 2 ? 'Public' : 'Internal',
        if (status > 0) 'ticket_status': status,
        'ticket_reply_time_worked':
            '${two(timeWorked.inHours)}:${two(timeWorked.inMinutes % 60)}:${two(timeWorked.inSeconds % 60)}',
      });
      if (!resp.success) return (ok: false, error: resp.message ?? 'Failed');
      return (ok: true, error: null);
    } on ApiException catch (e) {
      return (ok: false, error: e.message);
    }
  }

  /// Edits subject/details/priority on an existing ticket. Uses the REST
  /// `tickets/update` endpoint, which keeps every field it isn't sent, so a
  /// ticket's other assets, tags and schedule stay as they were. Falls back
  /// to the web form on servers without that endpoint.
  ///
  /// If [newClientId] is provided and differs from the current client, the
  /// ticket is moved to that client first through the web UI (no API for
  /// it), which resets the contact to 0.
  Future<({bool ok, String? error})> edit({
    required int ticketId,
    String? subject,
    String? details,
    String? priority,
    int? newClientId,
  }) async {
    final web = ref.read(itflowWebClientProvider);
    final current = await get(ticketId);
    if (current == null) {
      return (ok: false, error: 'Ticket $ticketId not found.');
    }
    try {
      var clientId = current.clientId ?? 0;
      var effectiveContactId = current.contactId ?? 0;
      if (newClientId != null && newClientId != clientId) {
        if (web == null) {
          return (
            ok: false,
            error:
                'Moving a ticket to another client needs agent email + password in Settings.'
          );
        }
        await web.changeTicketClient(
          ticketId: ticketId,
          newClientId: newClientId,
          newContactId: 0,
        );
        clientId = newClientId;
        effectiveContactId = 0;
      }

      final client = requireClient(ref);
      try {
        final resp = await client.post('tickets', 'update', body: {
          'ticket_id': ticketId,
          'client_id': clientId,
          'ticket_subject': subject ?? current.subject ?? '',
          'ticket_details': details ?? current.details ?? '',
          'ticket_priority': priority ?? current.priority ?? 'Medium',
        });
        if (resp.success) return (ok: true, error: null);
        // "no rows changed" is how ITFlow answers an edit that changed
        // nothing; that isn't a failure.
        if ((resp.message ?? '').contains('no rows changed')) {
          return (ok: true, error: null);
        }
        if (web == null) return (ok: false, error: resp.message);
      } on ApiException catch (e) {
        if (web == null || e.statusCode != 404) {
          return (ok: false, error: e.message);
        }
      }

      // Older servers: drive the web edit form with every current value.
      final r = current.raw;
      String dueFormatted = '';
      final due = toDate(r['ticket_due_at']);
      if (due != null) {
        // edit_ticket expects Y-m-d\TH:i (HTML <input type="datetime-local">)
        dueFormatted = due.toIso8601String().substring(0, 16);
      }
      await web.editTicket(
        ticketId: ticketId,
        subject: subject ?? current.subject ?? '',
        details: details ?? current.details ?? '',
        priority: priority ?? current.priority ?? 'Medium',
        billable: current.billable ? 1 : 0,
        contactId: effectiveContactId,
        assignedTo: current.assignedTo ?? 0,
        categoryId: toInt(r['ticket_category']) ?? 0,
        vendorId: toInt(r['ticket_vendor_id']) ?? 0,
        assetId: current.assetId ?? 0,
        locationId: toInt(r['ticket_location_id']) ?? 0,
        projectId: toInt(r['ticket_project_id']) ?? 0,
        vendorTicketNumber:
            (r['ticket_vendor_ticket_number'] ?? '').toString(),
        due: dueFormatted,
      );
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e is ApiException ? e.message : e.toString());
    }
  }
}

final ticketRepositoryProvider =
    Provider<TicketRepository>((ref) => TicketRepository(ref));

/// Number of tickets loaded so far during a paginated fetch.
/// Updates as each page arrives; useful for "Loading N tickets…" UI.
class TicketLoadProgress extends Notifier<int> {
  @override
  int build() => 0;
  void set(int value) => state = value;
}

final ticketLoadProgressProvider =
    NotifierProvider<TicketLoadProgress, int>(TicketLoadProgress.new);

final ticketsProvider =
    FutureProvider.autoDispose<List<Ticket>>((ref) async {
  // Wait for credentials to be loaded from secure storage before fetching.
  await ref.watch(credentialsProvider.future);
  final repo = ref.read(ticketRepositoryProvider);
  return repo.listAll(
    onProgress: (n) =>
        ref.read(ticketLoadProgressProvider.notifier).set(n),
  );
});

final ticketProvider =
    FutureProvider.autoDispose.family<Ticket?, int>((ref, id) async {
  await ref.watch(credentialsProvider.future);
  return ref.read(ticketRepositoryProvider).get(id);
});

/// A ticket's conversation, newest first. Read from the REST API
/// (`ticket_replies/read`) when the server has it; otherwise scraped from
/// the agent ticket page, which needs web credentials.
final ticketRepliesProvider = FutureProvider.autoDispose
    .family<List<TicketReply>, int>((ref, id) async {
  await ref.watch(credentialsProvider.future);
  final web = ref.read(itflowWebClientProvider);
  try {
    final client = requireClient(ref);
    final out = <TicketReply>[];
    var offset = 0;
    const pageSize = 200;
    while (true) {
      final resp = await client.get('ticket_replies', 'read', query: {
        'ticket_id': id,
        'limit': pageSize,
        'offset': offset,
      });
      final rows = resp.rows;
      out.addAll(rows
          .where((r) => r['ticket_reply_archived_at'] == null)
          .map((r) => ticketReplyFromApi(r)));
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    // ITFlow reads them oldest first; the app shows newest first like the
    // ticket page does.
    out.sort((a, b) => b.id.compareTo(a.id));
    return out;
  } on ApiException catch (e) {
    if (web == null) rethrow;
    // 404: an older server without the endpoint. Anything else (a role that
    // can't read replies over the API): the agent page may still show them.
    if (e.statusCode != 404 && e.statusCode != 403) rethrow;
  }
  return web.fetchTicketReplies(id);
});

typedef ReplyStatus = ({int id, String name, bool selected});

/// Statuses a reply can move the ticket to. Read from the instance's own
/// reply form when web credentials are set (statuses are configurable);
/// otherwise ITFlow's built-in Open / On Hold / Resolved, with the ticket's
/// current status picked.
final ticketReplyStatusesProvider = FutureProvider.autoDispose
    .family<List<ReplyStatus>, int>((ref, ticketId) async {
  await ref.watch(credentialsProvider.future);
  final web = ref.read(itflowWebClientProvider);
  if (web != null) {
    try {
      final list = await web.fetchReplyStatuses(ticketId);
      if (list.isNotEmpty) return list;
    } catch (_) {/* fall back to the built-ins */}
  }
  final ticket = await ref.read(ticketRepositoryProvider).get(ticketId);
  final current = ticket?.statusId ?? 2;
  const builtIn = {2: 'Open', 3: 'On Hold', 4: 'Resolved'};
  return [
    for (final e in builtIn.entries)
      (id: e.key, name: e.value, selected: e.key == current),
  ];
});

/// Agent names by user id, from `technicians/read`. Empty when the server
/// or the key's role doesn't offer it; callers fall back to "User #id".
final technicianNamesProvider =
    FutureProvider.autoDispose<Map<int, String>>((ref) async {
  await ref.watch(credentialsProvider.future);
  try {
    final resp = await requireClient(ref)
        .get('technicians', 'read', query: {'limit': 500});
    return {
      for (final r in resp.rows)
        if (toInt(r['technician_id']) != null)
          toInt(r['technician_id'])!: (r['technician_name'] ?? '').toString(),
    };
  } catch (_) {
    return const {};
  }
});

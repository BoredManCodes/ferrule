import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  }) async {
    final client = requireClient(ref);
    final resp = await client.post('tickets', 'create', body: {
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

  Future<bool> resolve(int ticketId) async {
    final client = requireClient(ref);
    final resp = await client.post('tickets', 'resolve', body: {
      'ticket_id': ticketId,
    });
    return resp.success;
  }

  /// Edits subject/details/priority on an existing ticket (web UI route — the
  /// v1 API has no ticket update endpoint). Preserves every other field by
  /// reading the current ticket first.
  ///
  /// If [newClientId] is provided and differs from the current client, the
  /// ticket is reassigned to that client first (which resets the contact to 0).
  Future<({bool ok, String? error})> edit({
    required int ticketId,
    String? subject,
    String? details,
    String? priority,
    int? newClientId,
  }) async {
    final web = ref.read(itflowWebClientProvider);
    if (web == null) {
      return (
        ok: false,
        error:
            'Agent email + password not set. Add them in Settings to enable edits.'
      );
    }
    final current = await get(ticketId);
    if (current == null) {
      return (ok: false, error: 'Ticket $ticketId not found.');
    }
    try {
      // Handle client change first so subsequent edit_ticket sees the right
      // contact context. ITFlow zeroes the contact when client changes.
      var effectiveContactId = current.contactId ?? 0;
      if (newClientId != null && newClientId != (current.clientId ?? 0)) {
        await web.changeTicketClient(
          ticketId: ticketId,
          newClientId: newClientId,
          newContactId: 0,
        );
        effectiveContactId = 0;
      }

      final r = current.raw;
      String dueFormatted = '';
      final due = toDate(r['ticket_due_at']);
      if (due != null) {
        // edit_ticket expects Y-m-d\TH:i (HTML <input type="datetime-local">)
        final iso = due.toIso8601String();
        dueFormatted = iso.substring(0, 16);
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
      return (ok: false, error: e.toString());
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

/// Replies scraped from the agent ticket page. Requires web credentials.
final ticketRepliesProvider = FutureProvider.autoDispose
    .family<List<TicketReply>, int>((ref, id) async {
  await ref.watch(credentialsProvider.future);
  final web = ref.read(itflowWebClientProvider);
  if (web == null) return const [];
  return web.fetchTicketReplies(id);
});

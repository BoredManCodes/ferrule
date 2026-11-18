import 'package:ferrule/core/api/itflow_web_client.dart';
import 'package:ferrule/features/banners/agent_banners.dart';
import 'package:ferrule/features/tickets/reply_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Markup as ITFlow 26.11.9 renders it.
const _bannersHtml = '''
<div class="itflow-agent-banner is-danger d-flex align-items-start d-print-none" data-agent-banner="4" role="alert"><i class="fas fa-fw fa-exclamation-circle itflow-agent-banner-icon"></i><div class="min-w-0 flex-grow-1"><div class="itflow-agent-banner-title">Office closed Friday</div></div></div><div class="itflow-agent-banner is-warning alert alert-warning gap-2 d-flex align-items-start d-print-none" data-agent-banner="3" role="status"><i class="fas fa-fw fa-exclamation-triangle itflow-agent-banner-icon"></i><div class="min-w-0 flex-grow-1"><div class="itflow-agent-banner-title">On credit hold<span class="itflow-agent-banner-for">ITFlow Development Inc</span></div><div class="itflow-agent-banner-body">No work without approval from <a href="https://example.com">https://example.com</a></div></div><button type="button" class="btn-close" data-agent-banner-hide="3" aria-label="Hide"></button></div>
<div class="dropdown-menu">
<a class="dropdown-item ajax-modal" href="#" data-modal-url="modals/agent_banner/agent_banner_add.php?client_id=1">New Banner</a>
<a class="dropdown-item ajax-modal small" href="#" data-modal-url="modals/agent_banner/agent_banner_edit.php?id=3&client_id=1"><span class="itflow-announcement-dot is-warning me-2 ms-1"></span>On credit hold            </a>
<a class="dropdown-item ajax-modal small" href="#" data-modal-url="modals/agent_banner/agent_banner_edit.php?id=5&client_id=1"><span class="itflow-announcement-dot is-info me-2 ms-1"></span>Audit next week <span class="text-body-secondary">(scheduled)</span></a>
</div>
''';

void main() {
  test('banners showing on a client page', () {
    final st = parseClientBannerState(_bannersHtml);
    expect(st.canEdit, isTrue);
    expect(st.showing.map((b) => b.id), [4, 3]);
    final urgent = st.showing.first;
    expect(urgent.tone, BannerTone.danger);
    expect(urgent.hideable, isFalse);
    expect(urgent.clientName, isNull);
    final warn = st.showing[1];
    expect(warn.title, 'On credit hold');
    expect(warn.clientName, 'ITFlow Development Inc');
    expect(warn.hideable, isTrue);
    expect(warn.bodyHtml, contains('example.com'));
    expect(st.clientBanners.map((b) => b.id), [3, 5]);
    expect(st.clientBanners[1].title, 'Audit next week');
    expect(st.clientBanners[1].status, 'Scheduled');
  });

  test('no banners on an older server', () {
    final st = parseClientBannerState('<html><body>nothing</body></html>');
    expect(st.canEdit, isFalse);
    expect(st.showing, isEmpty);
  });

  test('banner form', () {
    const html = '''
<input type="hidden" name="csrf_token" value="x">
<input type="text" name="title" value="On credit hold">
<textarea name="body">Call Sam</textarea>
<select name="tone"><option value="info">Notice</option><option value="warning" selected>Heads up</option><option value="danger">Urgent</option></select>
<input type="hidden" name="client_id" value="1">
<input type="datetime-local" name="starts_at" value="2026-11-18T09:00">
<input type="datetime-local" name="ends_at" value="">
<a class="btn" href="/agent/post.php?archive_agent_banner=3&csrf_token=x">Archive</a>''';
    final f = parseBannerForm(html, id: 3);
    expect(f.title, 'On credit hold');
    expect(f.body, 'Call Sam');
    expect(f.tone, 'warning');
    expect(f.tones.length, 3);
    expect(f.clientId, 1);
    expect(f.clientFixed, isTrue);
    expect(f.startsAt, '2026-11-18T09:00');
    expect(f.archived, isFalse);
  });

  test('flash errors, new and old markup', () {
    expect(
      ItflowWebClient.flashErrorFrom(
          '<div id="itflowFlashToast" class="toast show itflow-toast text-bg-danger border-0"><div class="toast-body">Pick one of your <strong>vendors</strong></div></div>'),
      'Pick one of your vendors',
    );
    expect(
      ItflowWebClient.flashErrorFrom(
          '<div id="itflowFlashToast" class="toast show text-bg-success"><div class="toast-body">Saved</div></div>'),
      isNull,
    );
    expect(
      ItflowWebClient.flashErrorFrom(
          'toastr["error"]("Invalid \\"amount\\"")'),
      r'Invalid \"amount\"',
    );
    expect(ItflowWebClient.flashErrorFrom('<p>plain page</p>'), isNull);
  });

  test('reply from the API', () {
    final r = ticketReplyFromApi({
      'ticket_reply_id': '7',
      'ticket_reply': '<p>hi</p>',
      'ticket_reply_type': 'Internal',
      'ticket_reply_time_worked': '00:05:00',
      'ticket_reply_created_at': '2026-11-18 09:00:00',
      'ticket_reply_by_name': 'Develop User',
    });
    expect(r.id, 7);
    expect(r.type, ReplyType.internal);
    expect(r.authorInitials, 'DU');
    expect(r.hasTimeWorked, isTrue);
    expect(r.createdAgo, 'Nov 18, 9:00 AM');
  });
}

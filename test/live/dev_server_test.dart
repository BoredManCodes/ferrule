// Pre-deploy checks against a live ITFlow server (by default the public
// develop instance, which tracks upstream's develop branch and resets
// itself). Every run starts from nothing: it signs in, has the app create
// its own API key the way first-run setup does, seeds the records it needs,
// then drives every feature through the app's real repositories and web
// client.
//
// Skipped unless FERRULE_LIVE=1, so plain `flutter test` stays offline:
//   FERRULE_LIVE=1 flutter test test/live
// Point it elsewhere with FERRULE_LIVE_URL / _EMAIL / _PASSWORD (the account
// must be an admin, and needs no 2FA).
@Tags(['live'])
library;

import 'dart:io';

import 'package:ferrule/core/api/api_response.dart';
import 'package:ferrule/core/api/itflow_client.dart';
import 'package:ferrule/core/api/itflow_web_client.dart';
import 'package:ferrule/core/api/providers.dart';
import 'package:ferrule/core/auth/api_key_provisioning.dart';
import 'package:ferrule/core/storage/secure_store.dart';
import 'package:ferrule/features/assets/asset_repository.dart';
import 'package:ferrule/features/banners/agent_banners.dart';
import 'package:ferrule/features/clients/client_repository.dart';
import 'package:ferrule/features/credentials/credential_repository.dart';
import 'package:ferrule/features/tickets/reply_model.dart';
import 'package:ferrule/features/tickets/ticket_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _env = Platform.environment;
final _live = _env['FERRULE_LIVE'] == '1';
final _url = _env['FERRULE_LIVE_URL'] ?? 'https://develop.dev.itflow.org';
// The develop instance prints its own login on the sign-in page.
final _email = _env['FERRULE_LIVE_EMAIL'] ?? 'dev@itflow.org';
final _password = _env['FERRULE_LIVE_PASSWORD'] ?? 'dev@itflow.org';

/// Credentials kept in memory instead of the OS keystore.
class _MemoryStore extends SecureStore {
  Credentials? c;
  @override
  Future<Credentials?> read() async => c;
  @override
  Future<void> save(Credentials creds) async => c = creds;
  @override
  Future<void> clear() async => c = null;
}

void main() {
  late Credentials creds;
  late ProviderContainer container;
  late ItflowClient api;
  late ItflowWebClient web;
  final stamp = DateTime.now().millisecondsSinceEpoch;

  // Records the suite seeds and later tests use.
  late int clientId;
  late int ticketId;
  late int invoiceId;
  late int quoteId;

  Future<int> create(String module, Map<String, dynamic> body,
      {bool decrypt = false}) async {
    final r = await api.post(module, 'create', body: body, includeDecrypt: decrypt);
    expect(r.success, isTrue, reason: '$module create: ${r.message}');
    return r.insertId!;
  }

  setUpAll(() async {
    if (!_live) return;
    creds = await provisionCredentials(
        instanceUrl: _url, email: _email, password: _password);
    final store = _MemoryStore()..c = creds;
    container = ProviderContainer(
        overrides: [secureStoreProvider.overrideWithValue(store)]);
    await container.read(credentialsProvider.future);
    api = container.read(itflowClientProvider)!;
    web = container.read(itflowWebClientProvider)!;

    // Seed. The develop server comes back empty after a reset.
    clientId = await create('clients', {
      'client_name': 'Ferrule Predeploy $stamp',
      'client_type': 'Test',
    });
    await create('contacts', {
      'client_id': clientId,
      'contact_name': 'Pat Predeploy',
      'contact_email': 'pat$stamp@example.com',
      'contact_primary': 1,
    });
    await create('vendors', {'client_id': 0, 'vendor_name': 'Predeploy Vendor $stamp'});
    await create('vendors', {'client_id': clientId, 'vendor_name': 'Client Vendor $stamp'});
    await create('locations', {
      'client_id': clientId,
      'location_name': 'Head Office',
      'location_address': '1 Main St',
      'location_primary': 1,
    });
    await create('domains', {
      'client_id': clientId,
      'domain_name': 'predeploy$stamp.test',
      'domain_expire': '2030-01-01',
    });
    await create('networks', {
      'client_id': clientId,
      'network_name': 'LAN',
      'network': '10.9.0.0/24',
      'network_gateway': '10.9.0.1',
    });
    await create('documents', {
      'client_id': clientId,
      'document_name': 'Runbook',
      'document_content': '<p>Steps</p>',
    });
    await create('products', {'product_name': 'Labour $stamp', 'product_price': 120});
    await create('certificates', {
      'client_id': clientId,
      'certificate_name': 'Web',
      'certificate_domain': 'predeploy$stamp.test',
      'certificate_expire': '2030-01-01',
    });
    await create('software', {
      'client_id': clientId,
      'software_name': 'Office',
      'software_type': 'SaaS',
    });
    await create('credentials', {
      'client_id': clientId,
      'credential_name': 'Router',
      'credential_username': 'admin',
      'credential_password': 'Pw-$stamp',
    }, decrypt: true);
    invoiceId = await create('invoices', {
      'client_id': clientId,
      'scope': 'Support',
      'items': [
        {'name': 'Labour', 'qty': 2, 'price': 120}
      ],
    });
    quoteId = await create('quotes', {
      'client_id': clientId,
      'scope': 'Laptop',
      'items': [
        {'name': 'Laptop', 'qty': 1, 'price': 1500}
      ],
    });
    // Only a sent invoice takes payments.
    await web.postAgentForm({
      'mark_invoice_sent': '1',
      'invoice_id': invoiceId,
      'sent_method': 'Other',
    }, referer: '$_url/agent/invoice.php?invoice_id=$invoiceId');

    final t = await container.read(ticketRepositoryProvider).create(
          subject: 'Predeploy ticket $stamp',
          details: 'Created by the pre-deploy suite',
          priority: 'Low',
          clientId: clientId,
        );
    expect(t.error, isNull);
    ticketId = t.id!;
  });

  tearDownAll(() {
    if (_live) container.dispose();
  });

  group('setup', skip: !_live, () {
    test('provisioned key is managed and works', () async {
      expect(creds.apiKeyManaged, isTrue);
      expect(creds.apiKeyId, isNotNull);
      final r = await api.get('clients', 'read', query: {'limit': 1});
      expect(r.success, isTrue);
    });

    test('branding: name and accent', () async {
      final b = await web.fetchInstanceBranding();
      expect(b.name, isNotNull);
      expect(b.accent, isNotNull);
    });

    test('rejected login is reported', () async {
      final bad = ItflowWebClient(baseUrl: _url, email: _email, password: 'wrong-$stamp');
      await expectLater(bad.login(), throwsA(isA<ApiException>()));
    });
  });

  group('API reads', skip: !_live, () {
    for (final m in [
      'clients', 'contacts', 'assets', 'tickets', 'invoices', 'quotes',
      'expenses', 'products', 'vendors', 'locations', 'networks',
      'certificates', 'software', 'documents', 'domains', 'payments',
    ]) {
      test(m, () async {
        final r = await api.get(m, 'read', query: {'limit': 5});
        expect(r.success || (r.message ?? '').contains('No resource'), isTrue,
            reason: r.message);
      });
    }

    test('line items', () async {
      final i = await api.get('invoice_items', 'read', query: {'invoice_id': invoiceId});
      expect(i.rows, isNotEmpty);
      final q = await api.get('quote_items', 'read', query: {'quote_id': quoteId});
      expect(q.rows, isNotEmpty);
    });

    test('vault decrypts with the provisioned password', () async {
      final repo = container.read(credentialRepositoryProvider);
      final page = await repo.fetchPage(offset: 0, pageSize: 500);
      final ours = page.where((c) => c.name == 'Router' && c.clientId == clientId);
      expect(ours, isNotEmpty);
      expect(ours.first.password, 'Pw-$stamp');
    });
  });

  group('vault + assets writes', skip: !_live, () {
    test('credential create and update', () async {
      final repo = container.read(credentialRepositoryProvider);
      final c = await repo.create({
        'name': 'Switch $stamp',
        'username': 'root',
        'password': 'first',
        'client_id': clientId,
      });
      expect(c.error, isNull);
      final u = await repo.update(c.id!, {
        'name': 'Switch $stamp',
        'username': 'root',
        'password': 'second',
        'client_id': clientId,
      });
      expect(u.ok, isTrue, reason: u.error);
      expect((await repo.get(c.id!))?.password, 'second');
    });

    test('asset create, update, delete', () async {
      final repo = container.read(assetRepositoryProvider);
      final a = await repo.create({
        'name': 'PC-$stamp',
        'type': 'Desktop',
        'client_id': clientId,
      });
      expect(a.error, isNull);
      final u = await repo.update(a.id!, {
        'name': 'PC-$stamp-renamed',
        'type': 'Desktop',
        'client_id': clientId,
      });
      expect(u.ok, isTrue, reason: u.error);
      expect((await repo.get(a.id!))?.name, 'PC-$stamp-renamed');
      final d = await repo.delete(a.id!);
      expect(d.ok, isTrue, reason: d.error);
    });

    test('client archive and unarchive', () async {
      final repo = container.read(clientRepositoryProvider);
      expect(await repo.archive(clientId), isTrue);
      expect(await repo.unarchive(clientId), isTrue);
    });
  });

  group('tickets', skip: !_live, () {
    test('created under the picked client', () async {
      final t = await container.read(ticketRepositoryProvider).get(ticketId);
      expect(t?.clientId, clientId);
    });

    test('edit over the API keeps other fields', () async {
      final repo = container.read(ticketRepositoryProvider);
      final r = await repo.edit(
          ticketId: ticketId, priority: 'High', details: 'Edited $stamp');
      expect(r.ok, isTrue, reason: r.error);
      final t = await repo.get(ticketId);
      expect(t?.priority, 'High');
      expect(t?.details, contains('Edited $stamp'));
      expect(t?.clientId, clientId);
    });

    test('reply statuses come from the server', () async {
      final list = await web.fetchReplyStatuses(ticketId);
      expect(list.map((s) => s.name), containsAll(['Open', 'Resolved']));
      // A New ticket has none picked: New isn't a status a reply may set.
      expect(list.where((s) => s.selected).length, lessThanOrEqualTo(1));
      expect(list.map((s) => s.id), isNot(contains(1)));
    });

    test('internal note over the web stays internal', () async {
      await web.addTicketReply(
        ticketId: ticketId,
        clientId: clientId,
        statusId: 2,
        hours: 0,
        minutes: 2,
        seconds: 0,
        replyText: 'web internal $stamp',
        replyType: 0,
      );
      final rows = (await api.get('ticket_replies', 'read', query: {'ticket_id': ticketId})).rows;
      final mine = rows.firstWhere((r) => '${r['ticket_reply']}'.contains('web internal $stamp'));
      expect(mine['ticket_reply_type'], 'Internal');
      expect(mine['ticket_reply_time_worked'], '00:02:00');
    });

    test('legacy internal code 3 never sends a text', () async {
      await web.addTicketReply(
        ticketId: ticketId,
        clientId: clientId,
        statusId: 2,
        hours: 0,
        minutes: 0,
        seconds: 0,
        replyText: 'legacy three $stamp',
        replyType: 3,
      );
      final rows = (await api.get('ticket_replies', 'read', query: {'ticket_id': ticketId})).rows;
      final mine = rows.firstWhere((r) => '${r['ticket_reply']}'.contains('legacy three $stamp'));
      expect(mine['ticket_reply_type'], 'Internal');
    });

    test('public note over the web', () async {
      await web.addTicketReply(
        ticketId: ticketId,
        clientId: clientId,
        statusId: 2,
        hours: 0,
        minutes: 0,
        seconds: 0,
        replyText: 'web public $stamp',
        replyType: 1,
      );
      final rows = (await api.get('ticket_replies', 'read', query: {'ticket_id': ticketId})).rows;
      final mine = rows.firstWhere((r) => '${r['ticket_reply']}'.contains('web public $stamp'));
      expect(mine['ticket_reply_type'], 'Public');
    });

    test('internal note over the API with time and status', () async {
      final r = await container.read(ticketRepositoryProvider).addReply(
            ticketId: ticketId,
            clientId: clientId,
            body: 'api internal $stamp',
            replyType: 0,
            status: 3,
            timeWorked: const Duration(minutes: 7),
          );
      expect(r.ok, isTrue, reason: r.error);
      final rows = (await api.get('ticket_replies', 'read', query: {'ticket_id': ticketId})).rows;
      final mine = rows.firstWhere((r) => '${r['ticket_reply']}'.contains('api internal $stamp'));
      expect(mine['ticket_reply_type'], 'Internal');
      expect(mine['ticket_reply_time_worked'], '00:07:00');
      final t = await container.read(ticketRepositoryProvider).get(ticketId);
      expect(t?.statusId, 3);
    });

    test('public note without email needs the web form', () async {
      final r = await container.read(ticketRepositoryProvider).addReply(
            ticketId: ticketId, body: 'x', replyType: 1);
      expect(r.ok, isFalse);
    });

    test('conversation: API and scraped page agree', () async {
      final fromApi = await container.read(ticketRepliesProvider(ticketId).future);
      final scraped = await web.fetchTicketReplies(ticketId);
      expect(fromApi, isNotEmpty);
      expect(scraped.length, fromApi.length);
      expect(scraped.first.id, fromApi.first.id);
      expect(scraped.first.type, fromApi.first.type);
      final internal = scraped.firstWhere((r) => r.bodyHtml.contains('web internal $stamp'));
      expect(internal.type, ReplyType.internal);
      expect(internal.authorName, isNotEmpty);
      expect(internal.timeWorked, isNotNull);
    });

    test('resolve with an all-clients key', () async {
      final r = await container
          .read(ticketRepositoryProvider)
          .resolve(ticketId, clientId: clientId);
      expect(r.ok, isTrue, reason: r.error);
      final t = await container.read(ticketRepositoryProvider).get(ticketId);
      expect(t?.isResolved, isTrue);
    });
  });

  group('web forms', skip: !_live, () {
    test('trip: form, add, list', () async {
      final f = await web.fetchTripAddForm();
      expect(f.drivers, isNotEmpty);
      expect(f.defaultDriverId, isNotNull);
      await web.addTrip(
        csrfToken: f.csrfToken,
        date: '2026-11-18',
        miles: 12.5,
        source: 'Office',
        destination: 'Site $stamp',
        purpose: 'Predeploy',
        driverId: f.defaultDriverId!,
        clientId: clientId,
        roundtrip: true,
      );
      final list = await web.fetchTripList();
      final mine = list.firstWhere((t) => t.destination == 'Site $stamp');
      expect(mine.source, 'Office');
      expect(mine.purpose, 'Predeploy');
      expect(mine.roundtrip, isTrue);
      expect(mine.driver, isNotEmpty);
      expect(mine.miles, greaterThan(0));
    });

    test('expense with receipt', () async {
      final f = await web.fetchExpenseAddForm();
      expect(f.vendors, isNotEmpty);
      expect(f.categories, isNotEmpty);
      expect(f.accounts, isNotEmpty);
      await web.addExpense(
        csrfToken: f.csrfToken,
        date: '2026-11-18',
        amount: 12.34,
        accountId: f.defaultAccountId ?? f.accounts.first.id,
        vendorId: f.vendors.first.id,
        categoryId: f.categories.first.id,
        clientId: clientId,
        description: 'Predeploy expense $stamp',
        reference: 'R$stamp',
        receiptBytes: const [0x25, 0x50, 0x44, 0x46, 0x2d],
        receiptFileName: 'receipt.pdf',
      );
      final rows = (await api.get('expenses', 'read', query: {'limit': 500})).rows;
      expect(rows.any((e) => e['expense_description'] == 'Predeploy expense $stamp'), isTrue);
    });

    test('expense refusal is surfaced', () async {
      final f = await web.fetchExpenseAddForm();
      await expectLater(
        web.addExpense(
          csrfToken: f.csrfToken,
          date: '2026-11-18',
          amount: 1,
          accountId: f.accounts.first.id,
          vendorId: 0,
          categoryId: f.categories.first.id,
          clientId: 0,
          description: 'no vendor',
          reference: '',
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('payment on a sent invoice', () async {
      final f = await web.fetchInvoicePaymentForm(invoiceId);
      expect(f.balance, closeTo(240, 0.01));
      expect(f.accounts, isNotEmpty);
      expect(f.paymentMethods, isNotEmpty);
      expect(f.invoiceLabel, isNot(contains('#')));
      await web.addInvoicePayment(
        csrfToken: f.csrfToken,
        invoiceId: invoiceId,
        balance: f.balance,
        currencyCode: f.currencyCode,
        date: '2026-11-18',
        amount: 40,
        accountId: f.defaultAccountId ?? f.accounts.first.id,
        paymentMethod: f.paymentMethods.first,
      );
      final after = await web.fetchInvoicePaymentForm(invoiceId);
      expect(after.balance, closeTo(200, 0.01));
    });

    test('payment form on a draft says why', () async {
      final draft = await create('invoices', {
        'client_id': clientId,
        'scope': 'Draft',
        'items': [
          {'name': 'x', 'qty': 1, 'price': 1}
        ],
      });
      await expectLater(web.fetchInvoicePaymentForm(draft),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('draft'))));
    });

    test('invoice and quote PDFs', () async {
      final inv = await web.downloadInvoicePdf(invoiceId);
      expect(String.fromCharCodes(inv.take(5)), '%PDF-');
      final q = await web.downloadQuotePdf(quoteId);
      expect(String.fromCharCodes(q.take(5)), '%PDF-');
    });

    test('AI reword: text back, or the server\'s reason', () async {
      try {
        final out = await web.rewordText('this are a test');
        expect(out, isNotEmpty);
      } on ApiException catch (e) {
        expect(e.message, contains('AI'));
      }
    });
  });

  group('agent banners', skip: !_live, () {
    late AgentBannerRepository repo;
    setUpAll(() {
      if (_live) repo = container.read(agentBannerRepositoryProvider)!;
    });

    test('client banner: post, show, hide, edit, archive, restore, delete', () async {
      final form = await repo.loadForm(clientId: clientId);
      expect(form.clientFixed, isTrue);
      expect(form.clientId, clientId);
      await repo.save(
        title: 'Credit hold $stamp',
        body: 'Ask accounts first',
        tone: 'warning',
        clientId: clientId,
        startsAt: '',
        endsAt: '',
      );
      var st = await repo.forClient(clientId);
      expect(st.canEdit, isTrue);
      final shown = st.showing.firstWhere((b) => b.title == 'Credit hold $stamp');
      expect(shown.tone, BannerTone.warning);
      expect(shown.hideable, isTrue);
      expect(st.clientBanners.map((b) => b.id), contains(shown.id));

      await repo.hide(shown.id);
      st = await repo.forClient(clientId);
      expect(st.showing.map((b) => b.id), isNot(contains(shown.id)));

      // Changing it brings it back for everyone who hid it.
      final edit = await repo.loadForm(id: shown.id, clientId: clientId);
      expect(edit.title, 'Credit hold $stamp');
      expect(edit.tone, 'warning');
      await repo.save(
        id: shown.id,
        title: 'Credit hold $stamp',
        body: 'Ask accounts first - updated',
        tone: 'warning',
        clientId: clientId,
        startsAt: '',
        endsAt: '',
      );
      st = await repo.forClient(clientId);
      expect(st.showing.map((b) => b.id), contains(shown.id));

      await repo.archive(shown.id);
      st = await repo.forClient(clientId);
      expect(st.showing.map((b) => b.id), isNot(contains(shown.id)));
      expect((await repo.loadForm(id: shown.id)).archived, isTrue);
      await repo.restore(shown.id);
      await repo.delete(shown.id);
      st = await repo.forClient(clientId);
      expect(st.clientBanners.map((b) => b.id), isNot(contains(shown.id)));
    });

    test('every-client urgent banner shows everywhere and can\'t be hidden', () async {
      await repo.save(
        title: 'Urgent $stamp',
        body: '',
        tone: 'danger',
        clientId: 0,
        startsAt: '',
        endsAt: '',
      );
      final global = await repo.globalBanners();
      final b = global.firstWhere((x) => x.title == 'Urgent $stamp');
      expect(b.tone, BannerTone.danger);
      expect(b.hideable, isFalse);
      expect(b.clientName, isNull);
      final onClient = await repo.forClient(clientId);
      expect(onClient.showing.first.id, b.id, reason: 'Urgent sorts first');
      final admin = await repo.adminList();
      expect(admin, isNotNull);
      expect(admin!.map((x) => x.id), contains(b.id));
      await repo.delete(b.id);
    });

    test('scheduled banner is listed but not shown yet', () async {
      final next = DateTime.now().add(const Duration(days: 3));
      String two(int n) => n.toString().padLeft(2, '0');
      await repo.save(
        title: 'Later $stamp',
        body: '',
        tone: 'info',
        clientId: clientId,
        startsAt: '${next.year}-${two(next.month)}-${two(next.day)}T09:00',
        endsAt: '',
      );
      final st = await repo.forClient(clientId);
      expect(st.showing.map((b) => b.title), isNot(contains('Later $stamp')));
      final listed = st.clientBanners.firstWhere((b) => b.title == 'Later $stamp');
      expect(listed.status, 'Scheduled');
      await repo.delete(listed.id);
    });
  });

  group('technician setup code', skip: !_live, () {
    test('admin makes a code; it signs in without admin rights', () async {
      final agents = await web.fetchApiKeyAgents();
      expect(agents, isNotEmpty);
      final code = await createSetupCode(creds,
          agentId: agents.first.id, agentName: agents.first.name);
      final scanned = SetupCode.tryParse(code.encode())!;
      final techCreds =
          scanned.toCredentials(webEmail: _email, webPassword: _password);
      expect(techCreds.apiKeyManaged, isFalse);
      expect(techCreds.apiKeyExpiresAt!.isAfter(
          DateTime.now().add(const Duration(days: 300))), isTrue);
      final client = ItflowClient(
          baseUrl: techCreds.instanceUrl,
          apiKey: techCreds.apiKey,
          decryptPassword: techCreds.decryptPassword);
      expect((await client.get('clients', 'read', query: {'limit': 1})).success,
          isTrue);
      final vault = await client.get('credentials', 'read',
          query: {'limit': 1}, includeDecrypt: true);
      expect(vault.success, isTrue, reason: vault.message);
      // The app never rotates a key it didn't make for itself.
      expect(await rotateApiKeyIfNeeded(techCreds, force: true), isNull);
      if (code.apiKeyId != null) await web.revokeApiKey(code.apiKeyId!);
    });
  });

  // Last: it replaces the key the other tests use.
  group('key rotation', skip: !_live, () {
    test('rotate now makes a new key and revokes the old one', () async {
      final oldKey = creds.apiKey;
      final updated = await rotateApiKeyIfNeeded(creds, force: true);
      expect(updated, isNotNull);
      expect(updated!.apiKey, isNot(oldKey));
      final fresh = ItflowClient(baseUrl: _url, apiKey: updated.apiKey);
      expect((await fresh.get('clients', 'read', query: {'limit': 1})).success, isTrue);
      final old = ItflowClient(baseUrl: _url, apiKey: oldKey);
      await expectLater(old.get('clients', 'read', query: {'limit': 1}),
          throwsA(isA<ApiException>()));
      // Not due yet: nothing happens.
      expect(await rotateApiKeyIfNeeded(updated), isNull);
    });
  });
}

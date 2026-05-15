import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;

import '../../features/expenses/expense_form_data.dart';
import '../../features/tickets/reply_model.dart';
import 'api_response.dart';

/// Drives the ITFlow web UI directly (login + agent/post.php).
/// Used for features the v1 API does not expose, e.g. logging time on a ticket reply.
class ItflowWebClient {
  final Dio _dio;
  final CookieJar _cookies = CookieJar();
  final String baseUrl;
  final String email;
  final String password;

  String? _csrfToken;
  bool _loggedIn = false;

  ItflowWebClient({
    required this.baseUrl,
    required this.email,
    required this.password,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30)
      ..followRedirects = false
      ..validateStatus = (s) => s != null && s < 500;
    _dio.interceptors.add(CookieManager(_cookies));
  }

  String get _root =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<void> _ensureLoggedIn() async {
    if (_loggedIn) return;
    await login();
  }

  /// Logs in. Throws [ApiException] with a useful message on failure.
  Future<void> login() async {
    final form = FormData.fromMap({
      'login': '1',
      'email': email,
      'password': password,
    });
    final resp = await _dio.post(
      '$_root/login.php',
      data: form,
      options: Options(
        headers: {'Referer': '$_root/login.php'},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );

    final body = resp.data?.toString() ?? '';
    final loc = resp.headers.value('location');
    // ITFlow redirects (302) away from login.php on success.
    final redirectedAway =
        loc != null && !loc.toLowerCase().contains('login.php');
    final mfaRequired = body.toLowerCase().contains('mfa') ||
        body.toLowerCase().contains('two-factor');
    final lockedOut = resp.statusCode == 429 ||
        body.contains('Too Many Requests') ||
        body.contains('blocked due to repeated');

    if (lockedOut) {
      throw ApiException(
          'IP temporarily blocked by ITFlow (too many failed logins). Wait ~10 min.',
          statusCode: 429);
    }
    if (mfaRequired && !redirectedAway) {
      throw ApiException(
          '2FA is enabled on this account. Web automation requires 2FA disabled (or a future TOTP prompt).');
    }
    if (!redirectedAway) {
      throw ApiException('Login failed — check email and password.');
    }

    _loggedIn = true;
    _csrfToken = null;
  }

  Future<String> _getCsrf() async {
    if (_csrfToken != null) return _csrfToken!;
    await _ensureLoggedIn();
    // After login, ITFlow's index.php 302s to /agent/<config_start_page>.
    // We need to follow that redirect to land on an HTML page that renders
    // a form with <input name="csrf_token">.
    final candidates = [
      '/index.php',
      '/agent/home.php',
      '/agent/dashboard.php',
      '/agent/tickets.php',
      '/agent/clients.php',
    ];
    String? sampleBody;
    for (final path in candidates) {
      final r = await _dio.get(
        '$_root$path',
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final body = r.data?.toString() ?? '';
      sampleBody ??= body.length > 300 ? body.substring(0, 300) : body;
      // Redirected back to login → session lapsed; re-login once.
      if (body.contains('name="email"') &&
          body.contains('name="password"') &&
          body.toLowerCase().contains('login')) {
        _loggedIn = false;
        await login();
        continue;
      }
      final token = _extractCsrf(body);
      if (token != null) {
        _csrfToken = token;
        return token;
      }
    }
    throw ApiException(
        'Could not extract CSRF token from agent UI. First response body started with: '
        '${sampleBody ?? "(empty)"}');
  }

  String? _extractCsrf(String body) {
    if (body.isEmpty) return null;
    // Fast path: regex on the raw HTML — modal includes inject the token via
    // <input type="hidden" name="csrf_token" value="..."> even when the parent
    // page contains lots of nested template noise.
    final re = RegExp(
      r'''name=["']csrf_token["']\s+value=["']([^"']+)["']''',
      caseSensitive: false,
    );
    final m = re.firstMatch(body);
    if (m != null) return m.group(1);
    final re2 = RegExp(
      r'''value=["']([^"']+)["']\s+name=["']csrf_token["']''',
      caseSensitive: false,
    );
    final m2 = re2.firstMatch(body);
    if (m2 != null) return m2.group(1);
    // Fall back to DOM parsing if the page is well-formed.
    try {
      final doc = html_parser.parse(body);
      final input = doc.querySelector('input[name="csrf_token"]');
      final v = input?.attributes['value'];
      if (v != null && v.isNotEmpty) return v;
      final meta = doc.querySelector('meta[name="csrf-token"]');
      final c = meta?.attributes['content'];
      if (c != null && c.isNotEmpty) return c;
    } catch (_) {}
    return null;
  }

  /// Probes the agent UI for the AdminLTE accent color name (e.g. "pink",
  /// "blue"). ITFlow applies this via `accent-<name>` on the `<body>`. Returns
  /// null if the page didn't render or the class wasn't found.
  Future<String?> fetchInstanceAccent() async {
    final b = await fetchInstanceBranding();
    return b.accent;
  }

  /// Fetches the configured company name (from login.php, no auth required)
  /// and the AdminLTE accent color (from an authenticated agent page — the
  /// login page doesn't carry the `accent-<name>` body class).
  Future<({String? accent, String? name})> fetchInstanceBranding() async {
    String? name;
    String? accent;

    // 1. Login page: cheap, public, and ITFlow renders the configured
    //    `config_login_company_name` as the title prefix.
    try {
      final r = await _dio.get(
        '$_root/login.php',
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (r.statusCode != null && r.statusCode! < 300) {
        name = _cleanTitle(_extractTitle(r.data?.toString() ?? ''));
      }
    } catch (_) {/* fall through to agent pages */}

    // 2. Agent pages: authenticated, but the only place the body carries
    //    `accent-<name>`. Also a fallback for the name if login.php was
    //    unreachable.
    try {
      await _ensureLoggedIn();
      for (final path in const [
        '/agent/home.php',
        '/agent/dashboard.php',
        '/index.php'
      ]) {
        if (accent != null && name != null) break;
        try {
          final r = await _dio.get(
            '$_root$path',
            options: Options(
              followRedirects: true,
              maxRedirects: 5,
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          // Skip 4xx — some instances don't expose every candidate path
          // (e.g. /agent/home.php may 404), and the server's 404 page often
          // has `<title>404 Not Found</title>`.
          if (r.statusCode == null || r.statusCode! >= 300) continue;
          final body = r.data?.toString() ?? '';
          if (body.isEmpty) continue;
          accent ??= RegExp(r'\baccent-([a-z][a-z0-9-]*)\b')
              .firstMatch(body)
              ?.group(1)
              ?.toLowerCase();
          name ??= _cleanTitle(_extractTitle(body));
        } catch (_) {/* try next */}
      }
    } catch (_) {/* keep whatever we got from login.php */}

    return (accent: accent, name: name);
  }

  String? _extractTitle(String body) {
    if (body.isEmpty) return null;
    return RegExp(
      r'<title[^>]*>\s*([^<]+?)\s*</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body)?.group(1);
  }

  String? _cleanTitle(String? raw) {
    if (raw == null) return null;
    var t = raw
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // ITFlow's login page renders "<company> | Login" — strip the suffix so
    // we end up storing just the company name.
    t = t
        .replaceFirst(RegExp(r'\s*\|\s*login\s*$', caseSensitive: false), '')
        .trim();
    if (t.isEmpty) return null;
    final lower = t.toLowerCase();
    if (lower == 'login' || lower == 'itflow' || lower == 'home') {
      return null;
    }
    // Defensive: even if a server 200s with an error page, drop obvious
    // HTTP-status-style titles ("404 Not Found", "403 Forbidden", etc.).
    if (RegExp(r'^[45]\d{2}\b').hasMatch(t)) return null;
    return t;
  }

  /// Scrapes the ticket page for the replies/comments thread.
  /// Replies are returned newest-first (matching the web UI's ORDER BY DESC).
  Future<List<TicketReply>> fetchTicketReplies(int ticketId) async {
    await _ensureLoggedIn();
    final resp = await _dio.get(
      '$_root/agent/ticket.php',
      queryParameters: {'ticket_id': ticketId},
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final body = resp.data?.toString() ?? '';
    if (body.contains('name="email"') && body.contains('name="password"')) {
      _loggedIn = false;
      await login();
      // Retry once.
      final retry = await _dio.get(
        '$_root/agent/ticket.php',
        queryParameters: {'ticket_id': ticketId},
        options: Options(followRedirects: true, maxRedirects: 5),
      );
      return _parseReplies(retry.data?.toString() ?? '');
    }
    return _parseReplies(body);
  }

  List<TicketReply> _parseReplies(String body) {
    if (body.isEmpty) return const [];
    final doc = html_parser.parse(body);
    final cards = doc.querySelectorAll('div.card.border-left');
    final out = <TicketReply>[];
    var pseudoId = 0;
    for (final card in cards) {
      final classes = (card.attributes['class'] ?? '').toLowerCase();
      ReplyType type;
      if (classes.contains('border-dark')) {
        type = ReplyType.internal;
      } else if (classes.contains('border-warning')) {
        type = ReplyType.client;
      } else if (classes.contains('border-info')) {
        type = ReplyType.public;
      } else {
        // Not a reply card we recognise (could be unrelated bordered card).
        continue;
      }

      final authorEl = card.querySelector('h3.card-title');
      final authorName = authorEl?.text.trim() ?? '';
      if (authorName.isEmpty) continue;

      // Try to recover the reply DB id from any archive/edit link inside the card.
      int id = ++pseudoId;
      for (final a in card.querySelectorAll('a')) {
        final href = a.attributes['href'] ?? '';
        final dataModalUrl = a.attributes['data-modal-url'] ?? '';
        final match = RegExp(
          r'(?:archive_ticket_reply=|id=)(\d+)',
        ).firstMatch('$href $dataModalUrl');
        if (match != null) {
          id = int.tryParse(match.group(1)!) ?? id;
          break;
        }
      }

      // Time worked
      String? timeWorked;
      for (final small in card.querySelectorAll('small')) {
        final txt = small.text;
        if (txt.contains('Time worked')) {
          final m = RegExp(r'(\d+\s*(?:s|m|h|d)|\d{1,2}:\d{2}(?::\d{2})?)')
              .firstMatch(small.text);
          if (m != null) timeWorked = m.group(1);
        }
      }

      // Created ago + raw timestamp
      String? createdAgo;
      String? createdAtRaw;
      final timestampDiv = card.querySelector('small.text-muted div[title]');
      if (timestampDiv != null) {
        createdAtRaw = timestampDiv.attributes['title'];
        createdAgo = timestampDiv.text.trim();
      }

      // Initials fallback
      String? initials;
      final initialsSpan = card.querySelector('span.fa-stack-1x');
      if (initialsSpan != null) {
        initials = initialsSpan.text.trim();
      }
      if (initials == null || initials.isEmpty) {
        final parts = authorName.split(RegExp(r'\s+'));
        initials = parts.take(2).map((p) => p.isEmpty ? '' : p[0]).join();
      }

      // Body
      final bodyEl = card.querySelector('div.card-body');
      final bodyHtml = bodyEl?.innerHtml ?? '';

      out.add(TicketReply(
        id: id,
        authorName: authorName,
        authorInitials: initials.toUpperCase(),
        type: type,
        bodyHtml: bodyHtml,
        timeWorked: timeWorked,
        createdAgo: createdAgo,
        createdAtRaw: createdAtRaw,
      ));
    }
    return out;
  }

  /// Edits a ticket via the web UI (the v1 API has no update endpoint).
  ///
  /// The web handler overwrites every column it touches, so callers should
  /// supply the *full* set of current values for fields they don't want
  /// changed. [extra] is merged onto the form data and wins on key collision.
  Future<void> editTicket({
    required int ticketId,
    required String subject,
    required String details,
    required String priority,
    required int billable,
    required int contactId,
    required int assignedTo,
    required int categoryId,
    required int vendorId,
    required int assetId,
    required int locationId,
    required int projectId,
    required String vendorTicketNumber,
    String due = '',
    Map<String, dynamic> extra = const {},
  }) async {
    final csrf = await _getCsrf();
    final form = FormData.fromMap({
      'edit_ticket': '1',
      'csrf_token': csrf,
      'ticket_id': ticketId,
      'subject': subject,
      'details': details,
      'priority': priority,
      'billable': billable,
      'contact_id': contactId,
      'assigned_to': assignedTo,
      'category_id': categoryId,
      'vendor_id': vendorId,
      'asset_id': assetId,
      'location_id': locationId,
      'project_id': projectId,
      'vendor_ticket_number': vendorTicketNumber,
      'due': due,
      ...extra,
    });
    await _postAgent(
      form: form,
      referer: '$_root/agent/ticket.php?ticket_id=$ticketId',
    );
  }

  /// Changes the ticket's client (and resets the contact since contacts are
  /// scoped to clients in ITFlow).
  Future<void> changeTicketClient({
    required int ticketId,
    required int newClientId,
    int newContactId = 0,
  }) async {
    final csrf = await _getCsrf();
    final form = FormData.fromMap({
      'change_client_ticket': '1',
      'csrf_token': csrf,
      'ticket_id': ticketId,
      'new_client_id': newClientId,
      'new_contact_id': newContactId,
    });
    await _postAgent(
      form: form,
      referer: '$_root/agent/ticket.php?ticket_id=$ticketId',
    );
  }

  /// Posts to /agent/post.php with a single retry if the session has lapsed.
  Future<void> _postAgent({
    required FormData form,
    required String referer,
  }) async {
    Future<Response> doPost(FormData f) => _dio.post(
          '$_root/agent/post.php',
          data: f,
          options: Options(
            headers: {'Referer': referer},
            contentType: Headers.formUrlEncodedContentType,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
    var resp = await doPost(form);
    final loc = resp.headers.value('location');
    if (loc != null && loc.toLowerCase().contains('login.php')) {
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      final csrf = await _getCsrf();
      // FormData is single-use; rebuild from the original fields.
      final retry = FormData();
      for (final field in form.fields) {
        retry.fields.add(MapEntry(
          field.key == 'csrf_token' ? 'csrf_token' : field.key,
          field.key == 'csrf_token' ? csrf : field.value,
        ));
      }
      resp = await doPost(retry);
    }
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw ApiException('Request failed: HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
  }

  /// Hits the web UI's AI reword endpoint (`/agent/ajax.php?ai_reword`).
  /// Returns the reworded text. Throws [ApiException] on transport failure.
  /// Returns the input unchanged if the server replies with its fallback
  /// "Failed to get a response from the AI API." string (indicates the admin
  /// hasn't configured a General-purpose AI model).
  Future<String> rewordText(String text) async {
    await _ensureLoggedIn();
    Future<Response> doPost() => _dio.post(
          '$_root/agent/ajax.php',
          queryParameters: {'ai_reword': ''},
          data: {'text': text},
          options: Options(
            headers: {
              'Referer': '$_root/agent/home.php',
              'X-Requested-With': 'XMLHttpRequest',
            },
            contentType: 'application/json',
            responseType: ResponseType.json,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
    var resp = await doPost();
    final loc = resp.headers.value('location');
    if (loc != null && loc.toLowerCase().contains('login.php')) {
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      resp = await doPost();
    }
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw ApiException('AI reword failed: HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
    final data = resp.data;
    String? out;
    if (data is Map) {
      out = data['rewordedText']?.toString();
    } else if (data is String) {
      // Some servers return JSON-as-string; try a loose grab.
      final m = RegExp(r'"rewordedText"\s*:\s*"((?:[^"\\]|\\.)*)"')
          .firstMatch(data);
      if (m != null) {
        out = m
            .group(1)!
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', r'\')
            .replaceAll(r'\n', '\n');
      }
    }
    if (out == null || out.isEmpty) {
      throw ApiException('AI reword returned no text.');
    }
    if (out.trim() == 'Failed to get a response from the AI API.') {
      throw ApiException(
          'AI reword unavailable — ITFlow admin needs to configure a General-purpose AI model.');
    }
    return out;
  }

  /// Submits a reply (and optional time worked) to the given ticket.
  /// [statusId]: ITFlow ticket status id (1=New, 2=Open, 3=In Progress, 4=Closed, etc.).
  /// [replyType]: 1=Public no email, 2=Public + email, 3=Internal.
  Future<void> addTicketReply({
    required int ticketId,
    required int clientId,
    required int statusId,
    required int hours,
    required int minutes,
    required int seconds,
    required String replyText,
    required int replyType,
  }) async {
    final csrf = await _getCsrf();
    final form = FormData.fromMap({
      'add_ticket_reply': '1',
      'csrf_token': csrf,
      'ticket_id': ticketId,
      'client_id': clientId,
      'status': statusId,
      'ticket_reply': replyText,
      'hours': hours,
      'minutes': minutes,
      'seconds': seconds,
      'public_reply_type': replyType,
    });
    final resp = await _dio.post(
      '$_root/agent/post.php',
      data: form,
      options: Options(
        headers: {'Referer': '$_root/ticket.php?ticket_id=$ticketId'},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );

    final loc = resp.headers.value('location');
    if (loc != null && loc.toLowerCase().contains('login.php')) {
      // Session expired mid-call. Re-login once and retry.
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      final csrf2 = await _getCsrf();
      final retry = FormData.fromMap({
        'add_ticket_reply': '1',
        'csrf_token': csrf2,
        'ticket_id': ticketId,
        'client_id': clientId,
        'status': statusId,
        'ticket_reply': replyText,
        'hours': hours,
        'minutes': minutes,
        'seconds': seconds,
        'public_reply_type': replyType,
      });
      final retryResp = await _dio.post(
        '$_root/agent/post.php',
        data: retry,
        options: Options(
          headers: {'Referer': '$_root/ticket.php?ticket_id=$ticketId'},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      if (retryResp.statusCode != null && retryResp.statusCode! >= 400) {
        throw ApiException('Reply failed: HTTP ${retryResp.statusCode}',
            statusCode: retryResp.statusCode);
      }
      return;
    }

    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw ApiException('Reply failed: HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
    // ITFlow's response is typically a 302 redirect to the ticket page on success.
  }

  /// Fetches the "New Expense" modal HTML and parses out CSRF token + the
  /// account/vendor/category/client option lists ITFlow shows on the web form.
  /// The modal endpoint returns `{"content": "...html..."}` JSON.
  Future<ExpenseAddFormData> fetchExpenseAddForm() async {
    await _ensureLoggedIn();
    Future<Response> doGet() => _dio.get(
          '$_root/agent/modals/expense/expense_add.php',
          options: Options(
            followRedirects: true,
            maxRedirects: 5,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
    var resp = await doGet();
    var raw = resp.data;
    // Session lapsed — body will be the login page HTML, not JSON.
    final bodyStr = raw is String ? raw : (raw?.toString() ?? '');
    if (bodyStr.contains('name="email"') && bodyStr.contains('name="password"')) {
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      resp = await doGet();
      raw = resp.data;
    }

    String htmlContent;
    if (raw is Map && raw['content'] is String) {
      htmlContent = raw['content'] as String;
    } else {
      final s = raw is String ? raw : (raw?.toString() ?? '');
      // Some responses come through as a JSON string when dio doesn't parse.
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map && decoded['content'] is String) {
          htmlContent = decoded['content'] as String;
        } else {
          htmlContent = s;
        }
      } catch (_) {
        htmlContent = s;
      }
    }

    final doc = html_parser.parse(htmlContent);
    final csrf =
        doc.querySelector('input[name="csrf_token"]')?.attributes['value'];
    if (csrf == null || csrf.isEmpty) {
      throw ApiException(
          'Could not load expense form — missing CSRF token. Are web credentials correct?');
    }

    List<NamedOption> parseOptions(String name, {bool stripBalance = false}) {
      final out = <NamedOption>[];
      final select = doc.querySelector('select[name="$name"]');
      if (select == null) return out;
      for (final opt in select.querySelectorAll('option')) {
        final value = opt.attributes['value'] ?? '';
        final id = int.tryParse(value);
        if (id == null || id == 0) continue;
        String label;
        if (stripBalance) {
          final left = opt.querySelector('div.float-left');
          label = (left?.text ?? opt.text).trim();
        } else {
          label = opt.text.trim();
        }
        if (label.isEmpty) label = 'Item #$id';
        out.add(NamedOption(id: id, name: label));
      }
      return out;
    }

    int? defaultAccount;
    final acctSel = doc.querySelector('select[name="account"]');
    if (acctSel != null) {
      final sel = acctSel.querySelector('option[selected]');
      if (sel != null) {
        defaultAccount = int.tryParse(sel.attributes['value'] ?? '');
        if (defaultAccount == 0) defaultAccount = null;
      }
    }

    return ExpenseAddFormData(
      csrfToken: csrf,
      accounts: parseOptions('account', stripBalance: true),
      vendors: parseOptions('vendor'),
      categories: parseOptions('category'),
      clients: parseOptions('client_id'),
      defaultAccountId: defaultAccount,
    );
  }

  /// Submits the "New Expense" form. [receiptBytes] + [receiptFileName] are
  /// optional; when provided, the file is attached under the `file` field
  /// (matching the web modal). Date must be `YYYY-MM-DD`.
  Future<void> addExpense({
    required String csrfToken,
    required String date,
    required double amount,
    required int accountId,
    required int vendorId,
    required int categoryId,
    required int clientId,
    required String description,
    required String reference,
    String? receiptFilePath,
    List<int>? receiptBytes,
    String? receiptFileName,
  }) async {
    await _ensureLoggedIn();

    String currentCsrf = csrfToken;

    FormData buildForm() {
      final form = FormData.fromMap({
        'add_expense': '1',
        'csrf_token': currentCsrf,
        'date': date,
        'amount': amount.toStringAsFixed(2),
        'account': accountId,
        'vendor': vendorId,
        'category': categoryId,
        'client_id': clientId,
        'description': description,
        'reference': reference,
      });
      if (receiptFileName != null && receiptFileName.isNotEmpty) {
        if (receiptBytes != null) {
          form.files.add(MapEntry(
            'file',
            MultipartFile.fromBytes(receiptBytes, filename: receiptFileName),
          ));
        } else if (receiptFilePath != null && receiptFilePath.isNotEmpty) {
          form.files.add(MapEntry(
            'file',
            MultipartFile.fromFileSync(receiptFilePath,
                filename: receiptFileName),
          ));
        }
      }
      return form;
    }

    Future<Response> doPost() => _dio.post(
          '$_root/agent/post.php',
          data: buildForm(),
          options: Options(
            headers: {'Referer': '$_root/agent/expenses.php'},
            followRedirects: false,
            validateStatus: (s) => s != null && s < 500,
          ),
        );

    var resp = await doPost();
    final loc = resp.headers.value('location');
    if (loc != null && loc.toLowerCase().contains('login.php')) {
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      currentCsrf = await _getCsrf();
      resp = await doPost();
    }

    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw ApiException('Add expense failed: HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }

    // CSRF rejection causes a redirect to index.php with an alert in session.
    // Distinguish that from the normal success redirect (back to expenses.php).
    final finalLoc = resp.headers.value('location') ?? '';
    if (finalLoc.toLowerCase().endsWith('/index.php') ||
        finalLoc.toLowerCase().contains('login.php')) {
      throw ApiException(
          'Server rejected the request — try logging out and back in.');
    }
  }
}

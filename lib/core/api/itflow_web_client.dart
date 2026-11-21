import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/dom.dart' show Element;
import 'package:html/parser.dart' as html_parser;

import '../../features/expenses/expense_form_data.dart';
import '../../features/invoices/payment_form_data.dart';
import '../../features/tickets/reply_model.dart';
import '../../features/trips/trip.dart';
import '../../features/trips/trip_form_data.dart';
import '../auth/mfa_bridge.dart';
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

  String get _root => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<void> _ensureLoggedIn() async {
    if (_loggedIn) return;
    await login();
  }

  Future<void>? _loginInFlight;

  /// Logs in. Throws [ApiException] with a useful message on failure.
  ///
  /// Accounts with 2FA: a stored remember-me cookie skips the code. Without
  /// one (or once it expires) [MfaBridge.prompt] asks for the code, and
  /// the login ticks ITFlow's "Remember this browser" so the next one
  /// doesn't have to.
  Future<void> login() =>
      _loginInFlight ??= _login().whenComplete(() => _loginInFlight = null);

  Future<void> _login({bool retried = false}) async {
    final remembered = await MfaBridge.rememberToken(_root, email);
    if (remembered != null) {
      await _cookies.saveFromResponse(Uri.parse('$_root/'), [
        Cookie(_rememberCookie, remembered)..path = '/',
      ]);
    }

    var resp = await _postLogin({
      'login': '1',
      'email': email,
      'password': password,
    });
    _throwIfLockedOut(resp);

    if (_pendingMfaToken(resp) != null) {
      final done = await MfaBridge.serialize(() async {
        final stored = await MfaBridge.rememberToken(_root, email);
        // Another login saved a fresh cookie while this one waited: use it.
        if (!retried && stored != null && stored != remembered) return null;
        // The cookie we sent didn't get us past 2FA, so it's dead.
        if (stored != null && stored == remembered) {
          await MfaBridge.saveRememberToken(_root, email, null);
        }
        return _completeMfa(resp);
      });
      if (done == null) return _login(retried: true);
      resp = done;
    }

    if (!_redirectedAway(resp)) {
      throw ApiException('Login failed. Check email and password.');
    }
    _loggedIn = true;
    _csrfToken = null;
  }

  static const _rememberCookie = 'rememberme';

  Future<Response<dynamic>> _postLogin(Map<String, String> fields) {
    return _dio.post(
      '$_root/login.php',
      data: FormData.fromMap(fields),
      options: Options(
        headers: {'Referer': '$_root/login.php'},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
  }

  // ITFlow redirects (302) away from login.php on success.
  bool _redirectedAway(Response<dynamic> resp) {
    final loc = resp.headers.value('location');
    return loc != null && !loc.toLowerCase().contains('login.php');
  }

  void _throwIfLockedOut(Response<dynamic> resp) {
    final body = resp.data?.toString() ?? '';
    if (body.contains('Too many incorrect 2FA codes')) {
      throw ApiException(
        'Too many wrong 2FA codes. ITFlow locks sign-in for 10 minutes.',
        statusCode: 429,
      );
    }
    if (resp.statusCode == 429 ||
        body.contains('Too Many Requests') ||
        body.contains('blocked due to repeated')) {
      throw ApiException(
        'IP temporarily blocked by ITFlow (too many failed logins). Wait ~10 min.',
        statusCode: 429,
      );
    }
  }

  /// The hidden `pending_mfa_token` ITFlow renders on its 2FA step, or
  /// null when the response isn't that step.
  String? _pendingMfaToken(Response<dynamic> resp) {
    if (_redirectedAway(resp)) return null;
    final body = resp.data?.toString() ?? '';
    if (!body.contains('pending_mfa_token')) return null;
    final v = html_parser
        .parse(body)
        .querySelector('input[name="pending_mfa_token"]')
        ?.attributes['value'];
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Asks for the 2FA code and submits it, up to three tries. Returns the
  /// successful response and stores ITFlow's new remember-me cookie.
  Future<Response<dynamic>> _completeMfa(Response<dynamic> first) async {
    var resp = first;
    String? error;
    for (var attempt = 0; attempt < 3; attempt++) {
      final pending = _pendingMfaToken(resp);
      if (pending == null) {
        throw ApiException('2FA sign-in timed out. Try again.');
      }
      final prompt = MfaBridge.prompt;
      if (prompt == null) {
        throw ApiException(
            'This account uses 2FA. Open Ferrule to enter a code.');
      }
      final code = await prompt(email: email, error: error);
      if (code == null || code.trim().isEmpty) {
        throw ApiException('Sign-in cancelled: a 2FA code is needed.');
      }
      resp = await _postLogin({
        'mfa_login': '1',
        'pending_mfa_token': pending,
        'current_code': code.replaceAll(RegExp(r'\s'), ''),
        'remember_me': 'on',
      });
      _throwIfLockedOut(resp);
      if (_redirectedAway(resp)) {
        final cookies = await _cookies.loadForRequest(Uri.parse('$_root/'));
        final fresh =
            cookies.where((c) => c.name == _rememberCookie).firstOrNull;
        if (fresh != null && fresh.value.isNotEmpty) {
          await MfaBridge.saveRememberToken(_root, email, fresh.value);
        }
        return resp;
      }
      error = 'That code didn\'t work. Check the time on your phone '
          'and try the newest code.';
    }
    throw ApiException('2FA code rejected three times. Sign in again.');
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
      '${sampleBody ?? "(empty)"}',
    );
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
    } catch (_) {
      /* fall through to agent pages */
    }

    // 2. Agent pages: authenticated, but the only place the body carries
    //    `accent-<name>`. Also a fallback for the name if login.php was
    //    unreachable.
    try {
      await _ensureLoggedIn();
      for (final path in const [
        '/agent/home.php',
        '/agent/dashboard.php',
        '/index.php',
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
          accent ??= _extractAccent(body);
          name ??= _cleanTitle(_extractTitle(body));
        } catch (_) {
          /* try next */
        }
      }
    } catch (_) {
      /* keep whatever we got from login.php */
    }

    return (accent: accent, name: name);
  }

  /// AdminLTE 3 builds put `accent-<name>` on the body; AdminLTE 4 builds
  /// use `data-lte-primary="<name>"` and a `theme-<name>` body class.
  String? _extractAccent(String body) {
    final bodyTag =
        RegExp(
          r'<body[^>]*>',
          caseSensitive: false,
        ).firstMatch(body)?.group(0) ??
        '';
    for (final re in [
      RegExp(r'''data-lte-primary=["']([a-z][a-z0-9-]*)["']'''),
      RegExp(r'\btheme-([a-z][a-z0-9-]*)\b'),
      RegExp(r'\baccent-([a-z][a-z0-9-]*)\b'),
    ]) {
      final m = re.firstMatch(bodyTag);
      if (m != null) return m.group(1)!.toLowerCase();
    }
    return RegExp(
      r'\baccent-([a-z][a-z0-9-]*)\b',
    ).firstMatch(body)?.group(1)?.toLowerCase();
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
  Future<List<TicketReply>> fetchTicketReplies(int ticketId) async =>
      _parseReplies(await _getTicketPage(ticketId));

  /// Ticket statuses an agent can pick when replying, read from the reply
  /// form on the ticket page (they're configurable per instance, so they
  /// can't be hardcoded). `selected` is the ticket's current status.
  Future<List<({int id, String name, bool selected})>> fetchReplyStatuses(
    int ticketId,
  ) async {
    final doc = html_parser.parse(await _getTicketPage(ticketId));
    final sel =
        doc.querySelector('select#ticket_reply_status') ??
        doc.querySelector('form select[name="status"]');
    final out = <({int id, String name, bool selected})>[];
    if (sel == null) return out;
    for (final opt in sel.querySelectorAll('option')) {
      final id = int.tryParse(opt.attributes['value'] ?? '');
      if (id == null || id == 0) continue;
      out.add((
        id: id,
        name: opt.text.trim(),
        selected: opt.attributes.containsKey('selected'),
      ));
    }
    return out;
  }

  Future<String> _getTicketPage(int ticketId) async {
    await _ensureLoggedIn();
    Future<String> doGet() async {
      final resp = await _dio.get(
        '$_root/agent/ticket.php',
        queryParameters: {'ticket_id': ticketId},
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return resp.data?.toString() ?? '';
    }

    final body = await doGet();
    if (body.contains('name="email"') && body.contains('name="password"')) {
      _loggedIn = false;
      _csrfToken = null;
      await login();
      return doGet();
    }
    return body;
  }

  List<TicketReply> _parseReplies(String body) {
    if (body.isEmpty) return const [];
    final doc = html_parser.parse(body);
    // AdminLTE 3 builds: `card border-left border-<type>`; AdminLTE 4
    // builds: `card ticket-reply border-start border-<type>` plus a
    // data-reply-group attribute.
    final cards = doc.querySelectorAll(
      'div.card.border-left, div.card.ticket-reply, div.card[data-reply-group]',
    );
    final out = <TicketReply>[];
    var pseudoId = 0;
    for (final card in cards) {
      final classes = (card.attributes['class'] ?? '').toLowerCase();
      final group = (card.attributes['data-reply-group'] ?? '').toLowerCase();
      ReplyType type;
      if (group == 'internal' || classes.contains('border-dark')) {
        type = ReplyType.internal;
      } else if (group == 'client' || classes.contains('border-warning')) {
        type = ReplyType.client;
      } else if (group == 'public' || classes.contains('border-info')) {
        type = ReplyType.public;
      } else {
        // Not a reply card we recognise (could be unrelated bordered card).
        continue;
      }

      final header = card.querySelector('.card-header') ?? card;
      final authorEl =
          card.querySelector('h3.card-title') ?? header.querySelector('strong');
      final authorName = authorEl?.text.trim() ?? '';
      if (authorName.isEmpty) continue;

      // Reply DB id: the card's own id="reply-N", else any archive/edit link.
      int id = ++pseudoId;
      final idAttr = RegExp(
        r'^reply-(\d+)$',
      ).firstMatch(card.attributes['id'] ?? '');
      if (idAttr != null) {
        id = int.parse(idAttr.group(1)!);
      } else {
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
      }

      final timeRe = RegExp(
        r'(\d+\s*(?:s|m|h|d)\b(?:\s*\d+\s*(?:s|m|h)\b)*|\d{1,2}:\d{2}(?::\d{2})?)',
      );
      String? timeWorked;
      String? createdAgo;
      String? createdAtRaw;
      // AdminLTE 4: <div class="small text-muted" title="Created: …">
      //   12 seconds ago · <i class="fa-clock"></i> 1m </div>
      final created = header.querySelector('[title^="Created"]');
      if (created != null) {
        createdAtRaw = created.attributes['title']!.replaceFirst(
          RegExp(r'^Created:\s*'),
          '',
        );
        final text = created.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        createdAgo = text.split('·').first.trim();
        if (created.querySelector('.fa-clock') != null && text.contains('·')) {
          final m = timeRe.firstMatch(text.substring(text.indexOf('·') + 1));
          if (m != null) timeWorked = m.group(1)!.trim();
        }
      } else {
        for (final small in card.querySelectorAll('small')) {
          if (small.text.contains('Time worked')) {
            final m = timeRe.firstMatch(small.text);
            if (m != null) timeWorked = m.group(1);
          }
        }
        final timestampDiv = card.querySelector('small.text-muted div[title]');
        if (timestampDiv != null) {
          createdAtRaw = timestampDiv.attributes['title'];
          createdAgo = timestampDiv.text.trim();
        }
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

      out.add(
        TicketReply(
          id: id,
          authorName: authorName,
          authorInitials: initials.toUpperCase(),
          type: type,
          bodyHtml: bodyHtml,
          timeWorked: timeWorked,
          createdAgo: createdAgo,
          createdAtRaw: createdAtRaw,
        ),
      );
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

  /// ITFlow answers a refused form the same way as a saved one: a 302 back
  /// with a flash message in the session. Follow the redirect once and throw
  /// the message if it was an error toast (AdminLTE 4: `text-bg-danger`;
  /// older builds: `toastr["error"]("...")`).
  Future<void> _raiseOnFlashError(Response resp) async {
    final loc = resp.headers.value('location');
    if (loc == null || loc.isEmpty) return;
    final target = Uri.parse('$_root/agent/').resolve(loc).toString();
    String body;
    try {
      final r = await _dio.get(
        target,
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      body = r.data?.toString() ?? '';
    } catch (_) {
      return; // can't tell; the post itself went through
    }
    final msg = flashErrorFrom(body);
    if (msg != null) throw ApiException(msg);
  }

  /// The error text of an ITFlow flash message in [body], or null if there
  /// is none or it isn't an error.
  static String? flashErrorFrom(String body) {
    String clean(String h) => h
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final toast = html_parser.parse(body).querySelector('#itflowFlashToast');
    if (toast != null) {
      final cls = toast.attributes['class'] ?? '';
      if (cls.contains('text-bg-danger')) {
        return clean(toast.querySelector('.toast-body')?.innerHtml ?? '');
      }
      return null;
    }
    final m = RegExp(r'toastr\["(error|danger)"\]\("((?:[^"\\]|\\.)*)"\)')
        .firstMatch(body);
    return m == null ? null : clean(m.group(2)!);
  }

  /// GETs an agent page as HTML, signing in again once if the session
  /// lapsed. [path] is relative to the instance root (e.g.
  /// `agent/client_overview.php`).
  Future<String> fetchAgentHtml(String path,
      {Map<String, dynamic>? query}) async {
    await _ensureLoggedIn();
    Future<String> doGet() async {
      final r = await _dio.get(
        '$_root/$path',
        queryParameters: query,
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return r.data?.toString() ?? '';
    }

    var body = await doGet();
    if (body.contains('name="email"') &&
        body.contains('name="password"') &&
        body.toLowerCase().contains('login')) {
      _loggedIn = false;
      _csrfToken = null;
      await login();
      body = await doGet();
    }
    return body;
  }

  /// Loads an ajax modal's HTML (see [_getModalHtml]).
  Future<String> fetchModalHtml(String path, {Map<String, dynamic>? query}) =>
      _getModalHtml(path, query: query);

  /// Posts [fields] (plus the session's CSRF token) to agent/post.php and
  /// throws the server's flash message if it refused.
  Future<void> postAgentForm(Map<String, dynamic> fields,
      {String? referer}) async {
    final csrf = await _getCsrf();
    await _postAgent(
      form: FormData.fromMap({...fields, 'csrf_token': csrf}),
      referer: referer ?? '$_root/agent/clients.php',
    );
  }

  /// Runs one of agent/post.php's GET actions (archive, delete, ...) with
  /// the session's CSRF token, throwing the flash message if it refused.
  ///
  /// [checkFlash] false for actions ITFlow reports in a red toast even when
  /// they worked (archiving and deleting).
  Future<void> agentGetAction(Map<String, dynamic> query,
      {String? referer, bool checkFlash = true}) async {
    final csrf = await _getCsrf();
    final resp = await _dio.get(
      '$_root/agent/post.php',
      queryParameters: {...query, 'csrf_token': csrf},
      options: Options(
        headers: {'Referer': referer ?? '$_root/agent/clients.php'},
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw ApiException('Request failed: HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
    if (checkFlash) await _raiseOnFlashError(resp);
  }

  /// Posts to agent/post.php for a handler that answers with no page at all
  /// (e.g. hiding a banner answers 204).
  Future<void> postAgentQuiet(Map<String, dynamic> fields) async {
    final csrf = await _getCsrf();
    final resp = await _dio.post(
      '$_root/agent/post.php',
      data: FormData.fromMap({...fields, 'csrf_token': csrf}),
      options: Options(
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw ApiException('Request failed: HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
  }

  /// Posts to /agent/post.php with a single retry if the session has lapsed.
  Future<Response> _postAgent({
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
        retry.fields.add(
          MapEntry(
            field.key == 'csrf_token' ? 'csrf_token' : field.key,
            field.key == 'csrf_token' ? csrf : field.value,
          ),
        );
      }
      resp = await doPost(retry);
    }
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw ApiException(
        'Request failed: HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    await _raiseOnFlashError(resp);
    return resp;
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
      throw ApiException(
        'AI reword failed: HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    final data = resp.data;
    String? out;
    if (data is Map && data['error'] is String) {
      // e.g. "No AI model is set up for General. Add one in Admin > AI Providers."
      throw ApiException('AI reword unavailable: ${data['error']}');
    }
    if (data is Map) {
      out = data['rewordedText']?.toString();
    } else if (data is String) {
      // Some servers return JSON-as-string; try a loose grab.
      final m = RegExp(
        r'"rewordedText"\s*:\s*"((?:[^"\\]|\\.)*)"',
      ).firstMatch(data);
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
        'AI reword unavailable — ITFlow admin needs to configure a General-purpose AI model.',
      );
    }
    return out;
  }

  /// ITFlow's reply form: 0=Internal, 1=Public note, 2=Public + email and,
  /// on newer builds, 3=Public + text message. Older app builds used 3 for
  /// Internal (old servers treated anything unknown as Internal), so 3 is
  /// mapped back to 0 here and never sent.
  static int _webReplyType(int t) => (t == 1 || t == 2) ? t : 0;

  /// Submits a reply (and optional time worked) to the given ticket.
  /// [statusId]: ITFlow ticket status id; read the instance's own list with
  /// [fetchReplyStatuses].
  /// [replyType]: 0=Internal, 1=Public no email, 2=Public + email.
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
      'public_reply_type': _webReplyType(replyType),
    });
    final resp = await _dio.post(
      '$_root/agent/post.php',
      data: form,
      options: Options(
        headers: {'Referer': '$_root/agent/ticket.php?ticket_id=$ticketId'},
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
        'public_reply_type': _webReplyType(replyType),
      });
      final retryResp = await _dio.post(
        '$_root/agent/post.php',
        data: retry,
        options: Options(
          headers: {'Referer': '$_root/agent/ticket.php?ticket_id=$ticketId'},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      if (retryResp.statusCode != null && retryResp.statusCode! >= 400) {
        throw ApiException(
          'Reply failed: HTTP ${retryResp.statusCode}',
          statusCode: retryResp.statusCode,
        );
      }
      await _raiseOnFlashError(retryResp);
      return;
    }

    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw ApiException(
        'Reply failed: HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    // A 302 back to the ticket page, with a flash saying how it went.
    await _raiseOnFlashError(resp);
  }

  /// Loads one of ITFlow's ajax modals and returns its HTML. The endpoint
  /// answers `{"content": "<html>"}`, or `{"error": "..."}` when it refuses
  /// (e.g. paying an invoice that has nothing owed), which is thrown as an
  /// [ApiException] carrying the server's own words.
  Future<String> _getModalHtml(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    await _ensureLoggedIn();
    Future<Response> doGet() => _dio.get(
      '$_root/$path',
      queryParameters: query,
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    var raw = (await doGet()).data;
    var bodyStr = raw is String ? raw : (raw?.toString() ?? '');
    if (raw is! Map &&
        bodyStr.contains('name="email"') &&
        bodyStr.contains('name="password"')) {
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      raw = (await doGet()).data;
      bodyStr = raw is String ? raw : (raw?.toString() ?? '');
    }
    Object? decoded = raw;
    if (raw is! Map) {
      try {
        decoded = jsonDecode(bodyStr);
      } catch (_) {
        decoded = null;
      }
    }
    if (decoded is Map) {
      final err = decoded['error'];
      if (err is String && err.isNotEmpty) {
        throw ApiException(err.replaceAll(RegExp(r'<[^>]+>'), '').trim());
      }
      if (decoded['content'] is String) return decoded['content'] as String;
    }
    return bodyStr;
  }

  /// Fetches the "New Expense" modal HTML and parses out CSRF token + the
  /// account/vendor/category/client option lists ITFlow shows on the web form.
  /// The modal endpoint returns `{"content": "...html..."}` JSON.
  Future<ExpenseAddFormData> fetchExpenseAddForm() async {
    final doc = html_parser.parse(
      await _getModalHtml('agent/modals/expense/expense_add.php'),
    );
    final csrf = doc
        .querySelector('input[name="csrf_token"]')
        ?.attributes['value'];
    if (csrf == null || csrf.isEmpty) {
      throw ApiException(
        'Could not load expense form — missing CSRF token. Are web credentials correct?',
      );
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
          form.files.add(
            MapEntry(
              'file',
              MultipartFile.fromBytes(receiptBytes, filename: receiptFileName),
            ),
          );
        } else if (receiptFilePath != null && receiptFilePath.isNotEmpty) {
          form.files.add(
            MapEntry(
              'file',
              MultipartFile.fromFileSync(
                receiptFilePath,
                filename: receiptFileName,
              ),
            ),
          );
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
      throw ApiException(
        'Add expense failed: HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }

    // CSRF rejection causes a redirect to index.php with an alert in session.
    // Distinguish that from the normal success redirect (back to expenses.php).
    final finalLoc = resp.headers.value('location') ?? '';
    if (finalLoc.toLowerCase().endsWith('/index.php') ||
        finalLoc.toLowerCase().contains('login.php')) {
      throw ApiException(
        'Server rejected the request — try logging out and back in.',
      );
    }
    await _raiseOnFlashError(resp);
  }

  /// Fetches the "New Trip" modal HTML and parses out CSRF + driver/client
  /// option lists. The selected driver is the current logged-in user, which is
  /// what ITFlow defaults to on the web form.
  Future<TripAddFormData> fetchTripAddForm() async {
    final doc = html_parser.parse(
      await _getModalHtml('agent/modals/trip/trip_add.php'),
    );
    final csrf = doc
        .querySelector('input[name="csrf_token"]')
        ?.attributes['value'];
    if (csrf == null || csrf.isEmpty) {
      throw ApiException(
        'Could not load trip form — missing CSRF token. Are web credentials correct?',
      );
    }

    final drivers = <NamedOption>[];
    int? defaultDriver;
    // `driver` on current builds, `user` on older ones.
    final userSel =
        doc.querySelector('select[name="driver"]') ??
        doc.querySelector('select[name="user"]');
    if (userSel != null) {
      for (final opt in userSel.querySelectorAll('option')) {
        final value = opt.attributes['value'] ?? '';
        final id = int.tryParse(value);
        if (id == null || id == 0) continue;
        final label = opt.text.trim().replaceFirst(RegExp(r'\s*\(me\)$'), '');
        drivers.add(
          NamedOption(id: id, name: label.isEmpty ? 'User #$id' : label),
        );
        if (opt.attributes.containsKey('selected')) {
          defaultDriver = id;
        }
      }
    }

    final clients = <NamedOption>[];
    final clientSel = doc.querySelector('select[name="client_id"]');
    if (clientSel != null) {
      for (final opt in clientSel.querySelectorAll('option')) {
        final value = opt.attributes['value'] ?? '';
        final id = int.tryParse(value);
        if (id == null || id == 0) continue;
        final label = opt.text.trim();
        clients.add(
          NamedOption(id: id, name: label.isEmpty ? 'Client #$id' : label),
        );
      }
    }

    return TripAddFormData(
      csrfToken: csrf,
      drivers: drivers,
      clients: clients,
      defaultDriverId: defaultDriver,
    );
  }

  /// Scrapes `/agent/trips.php` for recent trips. ITFlow has no JSON endpoint
  /// for trips, so we GET the agent listing page (forcing the all-time date
  /// range so we don't get the default narrow window) and parse the table.
  Future<List<Trip>> fetchTripList() async {
    await _ensureLoggedIn();
    Future<Response> doGet() => _dio.get(
      '$_root/agent/trips.php',
      queryParameters: {'canned_date': 'alltime'},
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    var resp = await doGet();
    var body = resp.data?.toString() ?? '';
    if (body.contains('name="email"') && body.contains('name="password"')) {
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      resp = await doGet();
      body = resp.data?.toString() ?? '';
    }

    final doc = html_parser.parse(body);
    final rows = doc.querySelectorAll('table tbody tr');
    final out = <Trip>[];
    for (final row in rows) {
      final route = row.querySelector('td.itflow-trip-route');
      if (route != null) {
        final t = _parseNewTripRow(row, route);
        if (t != null) out.add(t);
        continue;
      }
      final cells = row.querySelectorAll('td');
      if (cells.length < 6) continue;

      final firstA = cells[0].querySelector('a');
      final modalUrl = firstA?.attributes['data-modal-url'] ?? '';
      final idMatch = RegExp(r'id=(\d+)').firstMatch(modalUrl);
      if (idMatch == null) continue;
      final id = int.tryParse(idMatch.group(1)!);
      if (id == null) continue;

      final date = (firstA?.text ?? cells[0].text).trim();
      final driver = cells[1].text.trim();
      final purpose = cells[2].text.trim();
      final source = cells[3].text.trim();
      final destination = cells[4].text.trim();

      final milesCell = cells[5];
      final roundtrip = milesCell.querySelector('i.fa-sync-alt') != null;
      final milesNum = RegExp(r'[\d.]+').firstMatch(milesCell.text);
      final miles = milesNum == null
          ? 0.0
          : double.tryParse(milesNum.group(0)!) ?? 0.0;

      // The client column is omitted when the page is filtered by client.
      // Detect by total cell count: 8 cells means client column is present
      // (Date, Driver, Purpose, Source, Destination, Miles, Client, Action);
      // 7 cells means it's been filtered out.
      String? clientName;
      if (cells.length >= 8) {
        final raw = cells[6].text.trim();
        if (raw.isNotEmpty && raw != '-') clientName = raw;
      }

      out.add(
        Trip(
          id: id,
          date: date,
          driver: driver,
          purpose: purpose,
          source: source,
          destination: destination,
          miles: miles,
          roundtrip: roundtrip,
          clientName: clientName,
        ),
      );
    }
    return out;
  }

  /// Current (AdminLTE 4) trips table: checkbox, date (modal link), route
  /// cell (From → To, purpose under it), client (absent when filtered by
  /// client), driver badge, miles (round-trip total + sync icon), actions.
  Trip? _parseNewTripRow(Element row, Element route) {
    final link = row.querySelector('a[data-modal-url*="trip.php?id="]');
    final idMatch = RegExp(
      r'id=(\d+)',
    ).firstMatch(link?.attributes['data-modal-url'] ?? '');
    if (idMatch == null) return null;
    final id = int.parse(idMatch.group(1)!);
    final date = (link?.text ?? '').trim();

    final routeDiv = route.querySelector('div[title]');
    final routeTitle = routeDiv?.attributes['title'] ?? '';
    String source = '', destination = '';
    final arrow = routeTitle.indexOf('→');
    if (arrow >= 0) {
      source = routeTitle.substring(0, arrow).trim();
      destination = routeTitle.substring(arrow + 1).trim();
    } else {
      source = (routeDiv?.querySelector('span')?.text ?? '').trim();
    }
    final purposeEl = route.querySelector('div.small');
    final purpose = (purposeEl?.attributes['title'] ?? purposeEl?.text ?? '')
        .trim();

    final cells = row.querySelectorAll('td');
    final routeIdx = cells.indexOf(route);
    String? clientName;
    String driver = '';
    double miles = 0;
    bool roundtrip = false;
    for (var i = routeIdx + 1; i < cells.length; i++) {
      final c = cells[i];
      if (c.querySelector('.dropdown') != null) continue;
      final cls = c.attributes['class'] ?? '';
      if (cls.contains('text-end')) {
        roundtrip = c.querySelector('i.fa-sync-alt') != null;
        final m = RegExp(r'[\d.,]+').firstMatch(c.text);
        miles = double.tryParse(m?.group(0)?.replaceAll(',', '') ?? '') ?? 0;
      } else if (c.querySelector('.badge') != null) {
        driver = c.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        // The badge leads with the initials avatar ("DU Develop User").
        final initials = c.querySelector('small')?.text ?? '';
        if (initials.isNotEmpty && driver.startsWith(initials)) {
          driver = driver.substring(initials.length).trim();
        }
      } else {
        final raw = c.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (raw.isNotEmpty && raw != '-') clientName = raw;
      }
    }
    return Trip(
      id: id,
      date: date,
      driver: driver,
      purpose: purpose,
      source: source,
      destination: destination,
      miles: miles,
      roundtrip: roundtrip,
      clientName: clientName,
    );
  }

  /// Submits the "New Trip" form. [clientId] = 0 means no client. [roundtrip]
  /// is sent as 1/0 the same way the web checkbox does.
  Future<void> addTrip({
    required String csrfToken,
    required String date,
    required double miles,
    required String source,
    required String destination,
    required String purpose,
    required int driverId,
    required int clientId,
    bool roundtrip = false,
  }) async {
    await _ensureLoggedIn();
    String currentCsrf = csrfToken;

    FormData build() {
      return FormData.fromMap({
        'add_trip': '1',
        'csrf_token': currentCsrf,
        'date': date,
        'miles': miles.toStringAsFixed(1),
        'source': source,
        'destination': destination,
        'purpose': purpose,
        // Both spellings: `driver`/`round_trip` on current ITFlow,
        // `user`/`roundtrip` on older builds. Miles are one way; newer
        // builds double them for a round trip themselves.
        'driver': driverId,
        'user': driverId,
        'client_id': clientId,
        if (roundtrip) 'round_trip': '1',
        if (roundtrip) 'roundtrip': '1',
      });
    }

    Future<Response> doPost() => _dio.post(
      '$_root/agent/post.php',
      data: build(),
      options: Options(
        headers: {'Referer': '$_root/agent/trips.php'},
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    var resp = await doPost();
    final loc = resp.headers.value('location') ?? '';
    if (loc.toLowerCase().contains('login.php')) {
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      currentCsrf = await _getCsrf();
      resp = await doPost();
    }

    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw ApiException(
        'Add trip failed: HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }

    final finalLoc = resp.headers.value('location') ?? '';
    if (finalLoc.toLowerCase().endsWith('/index.php') ||
        finalLoc.toLowerCase().contains('login.php')) {
      throw ApiException(
        'Server rejected the request — try logging out and back in.',
      );
    }
    await _raiseOnFlashError(resp);
  }

  /// Loads the "Make Payment" modal for an invoice and parses out everything
  /// the form needs: CSRF token, current balance + currency, accounts and
  /// payment-method dropdowns. Mirrors [fetchExpenseAddForm].
  Future<PaymentAddFormData> fetchInvoicePaymentForm(int invoiceId) async {
    final doc = html_parser.parse(
      await _getModalHtml(
        'agent/modals/payment/payment_add.php',
        query: {'id': invoiceId},
      ),
    );
    final csrf = doc
        .querySelector('input[name="csrf_token"]')
        ?.attributes['value'];
    if (csrf == null || csrf.isEmpty) {
      throw ApiException('Could not load payment form — missing CSRF token.');
    }

    String hidden(String name) =>
        doc.querySelector('input[name="$name"]')?.attributes['value'] ?? '';
    // Older builds carry a hidden `balance`; newer ones prefill `amount`
    // with what is owed.
    final amountInput = doc
        .querySelector('input[name="amount"]')
        ?.attributes['value']
        ?.replaceAll(',', '');
    final balance =
        double.tryParse(hidden('balance')) ??
        double.tryParse(amountInput ?? '') ??
        0.0;
    final currency = hidden('currency_code');

    // Invoice label is rendered in the modal title: "<prefix><number>: Make Payment"
    final title = doc.querySelector('.modal-title')?.text.trim() ?? '';
    // "INV-1: Make Payment" on older builds, "Add Payment INV-1 · Client"
    // on newer ones.
    final labelMatch =
        RegExp(r'^(.+?):\s*Make Payment').firstMatch(title) ??
        RegExp(r'Add Payment\s+(\S+)').firstMatch(title);
    final invoiceLabel = labelMatch?.group(1)?.trim() ?? 'Invoice #$invoiceId';

    final accounts = <NamedOption>[];
    int? defaultAccount;
    final acctSel = doc.querySelector('select[name="account"]');
    if (acctSel != null) {
      for (final opt in acctSel.querySelectorAll('option')) {
        final value = opt.attributes['value'] ?? '';
        final id = int.tryParse(value);
        if (id == null || id == 0) continue;
        var label = opt.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (label.isEmpty) label = 'Account #$id';
        accounts.add(NamedOption(id: id, name: label));
        if (opt.attributes.containsKey('selected')) {
          defaultAccount = id;
        }
      }
    }

    final methods = <String>[];
    String? defaultMethod;
    final methodSel = doc.querySelector('select[name="payment_method"]');
    if (methodSel != null) {
      for (final opt in methodSel.querySelectorAll('option')) {
        // Payment methods submit by option text — no `value=` attribute on
        // real entries. Skip the "- Method of Payment -" placeholder, which
        // has value="".
        final value = opt.attributes['value'];
        final text = opt.text.trim();
        if (text.isEmpty ||
            (value != null && value.isEmpty && text.startsWith('-'))) {
          continue;
        }
        methods.add(text);
        if (opt.attributes.containsKey('selected')) {
          defaultMethod = text;
        }
      }
    }

    return PaymentAddFormData(
      csrfToken: csrf,
      invoiceId: invoiceId,
      invoiceLabel: invoiceLabel,
      balance: balance,
      currencyCode: currency,
      accounts: accounts,
      paymentMethods: methods,
      defaultAccountId: defaultAccount,
      defaultPaymentMethod: defaultMethod,
    );
  }

  /// Submits the "Make Payment" form to the agent post handler.
  Future<void> addInvoicePayment({
    required String csrfToken,
    required int invoiceId,
    required double balance,
    required String currencyCode,
    required String date,
    required double amount,
    required int accountId,
    required String paymentMethod,
    String reference = '',
    bool emailReceipt = false,
  }) async {
    await _ensureLoggedIn();
    String currentCsrf = csrfToken;

    FormData build() {
      return FormData.fromMap({
        'add_payment': '1',
        'csrf_token': currentCsrf,
        'invoice_id': invoiceId,
        'balance': balance.toStringAsFixed(2),
        'currency_code': currencyCode,
        'date': date,
        'amount': amount.toStringAsFixed(2),
        'account': accountId,
        'payment_method': paymentMethod,
        'reference': reference,
        if (emailReceipt) 'email_receipt': '1',
      });
    }

    Future<Response> doPost() => _dio.post(
      '$_root/agent/post.php',
      data: build(),
      options: Options(
        headers: {
          'Referer': '$_root/agent/invoice.php?invoice_id=$invoiceId',
        },
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    var resp = await doPost();
    if (resp.statusCode == 302) {
      final loc = resp.headers.value('location') ?? '';
      if (loc.toLowerCase().contains('login.php')) {
        _loggedIn = false;
        _csrfToken = null;
        await _ensureLoggedIn();
        currentCsrf = await _getCsrf();
        resp = await doPost();
      }
    }

    if (resp.statusCode == null ||
        (resp.statusCode! >= 300 && resp.statusCode != 302)) {
      throw ApiException(
        'Payment submission failed (status ${resp.statusCode}).',
        statusCode: resp.statusCode,
      );
    }

    final loc = resp.headers.value('location') ?? '';
    if (loc.toLowerCase().endsWith('/index.php') ||
        loc.toLowerCase().contains('login.php')) {
      throw ApiException(
        'Server rejected the payment — try logging out and back in.',
      );
    }
    // ITFlow validates `amount > balance` on the server and flashes an error
    // back via session; surface it.
    await _raiseOnFlashError(resp);
  }

  /// What a form would post untouched: text and hidden inputs, ticked
  /// boxes, each select's selected option (else its first), textareas.
  static Map<String, String> formDefaults(String html) {
    final doc = html_parser.parse(html);
    final out = <String, String>{};
    for (final el in doc.querySelectorAll('input, select, textarea')) {
      final name = el.attributes['name'];
      if (name == null || name.isEmpty || name.endsWith('[]')) continue;
      if (el.localName == 'select') {
        final opts = el.querySelectorAll('option');
        if (opts.isEmpty) continue;
        final pick = opts.firstWhere(
          (o) => o.attributes.containsKey('selected'),
          orElse: () => opts.first,
        );
        out[name] = pick.attributes['value'] ?? pick.text.trim();
      } else if (el.localName == 'textarea') {
        out[name] = el.text;
      } else {
        final type = (el.attributes['type'] ?? 'text').toLowerCase();
        if (type == 'submit' || type == 'button' || type == 'file') continue;
        if ((type == 'checkbox' || type == 'radio') &&
            !el.attributes.containsKey('checked')) {
          continue;
        }
        out[name] = el.attributes['value'] ?? (type == 'checkbox' ? 'on' : '');
      }
    }
    return out;
  }

  /// The invoice id in a post redirect like `invoice.php?invoice_id=42`.
  static int? invoiceIdFromLocation(String? loc) {
    if (loc == null) return null;
    final m = RegExp(r'invoice\.php\?(?:[^#]*&)?invoice_id=(\d+)').firstMatch(loc);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Makes a draft invoice for [clientId] through the web "New Invoice"
  /// form, keeping its defaults (category, discount). Returns its id.
  Future<int> createInvoice({
    required int clientId,
    required String scope,
    required String date,
  }) async {
    final fields = formDefaults(await _getModalHtml(
      'agent/modals/invoice/invoice_add.php',
      query: {'client_id': clientId},
    ));
    fields.remove('add_invoice');
    final csrf = await _getCsrf();
    final resp = await _postAgent(
      form: FormData.fromMap({
        ...fields,
        'csrf_token': fields['csrf_token']?.isNotEmpty == true
            ? fields['csrf_token']
            : csrf,
        'add_invoice': '1',
        'client_id': clientId,
        'client': clientId,
        'scope': scope,
        'date': date,
      }),
      referer: '$_root/agent/invoices.php?client_id=$clientId',
    );
    final id = invoiceIdFromLocation(resp.headers.value('location'));
    if (id == null) {
      throw ApiException('ITFlow made no invoice (no invoice id came back).');
    }
    return id;
  }

  /// Adds a typed-in line (qty 1) the way the invoice page's add field
  /// does, so ITFlow gives it the client's usual tax. Returns the line id.
  Future<int> addInvoiceLine({
    required int invoiceId,
    required String name,
    String description = '',
    required double price,
  }) async {
    final r = await _postAjax({
      'billing_item_add': '1',
      'type': 'invoice',
      'doc_id': '$invoiceId',
      'name': name,
      'description': description,
      'qty': '1',
      'price': price.toStringAsFixed(2),
    }, referer: '$_root/agent/invoice.php?invoice_id=$invoiceId');
    final id = int.tryParse('${r['item_id']}');
    if (id == null) throw ApiException('ITFlow did not add the line.');
    return id;
  }

  /// Changes one field of a line in place (price, qty, name, ...).
  Future<void> setInvoiceLineField({
    required int invoiceId,
    required int itemId,
    required String field,
    required String value,
  }) async {
    await _postAjax({
      'billing_item_set': '1',
      'type': 'invoice',
      'doc_id': '$invoiceId',
      'item_id': '$itemId',
      'field': field,
      'value': value,
    }, referer: '$_root/agent/invoice.php?invoice_id=$invoiceId');
  }

  /// Puts a ticket on an invoice without billing its time, so the ticket
  /// reads as billed and the invoice keeps the lines it has.
  Future<void> linkTicketToInvoice({
    required int invoiceId,
    required int ticketId,
  }) async {
    await _postAgent(
      form: FormData.fromMap({
        'add_ticket_to_invoice': '1',
        'csrf_token': await _getCsrf(),
        'invoice_id': invoiceId,
        'ticket_id': ticketId,
        'ticket_ids[]': ticketId,
      }),
      referer: '$_root/agent/invoice.php?invoice_id=$invoiceId',
    );
  }

  /// Marks an invoice sent (hand delivered), which is what lets the guest
  /// page take a card payment on it.
  Future<void> markInvoiceSent(int invoiceId) async {
    await _postAgent(
      form: FormData.fromMap({
        'mark_invoice_sent': '1',
        'csrf_token': await _getCsrf(),
        'invoice_id': invoiceId,
        'sent_method': 'Hand Delivered',
        'note': 'On-site payment',
      }),
      referer: '$_root/agent/invoice.php?invoice_id=$invoiceId',
    );
  }

  /// Posts to agent/ajax.php and returns its JSON, throwing the server's
  /// message when it answers `status: error`.
  Future<Map<String, dynamic>> _postAjax(
    Map<String, String> fields, {
    required String referer,
  }) async {
    Future<Response> doPost() async => _dio.post(
      '$_root/agent/ajax.php',
      data: {...fields, 'csrf_token': await _getCsrf()},
      options: Options(
        headers: {'Referer': referer, 'X-Requested-With': 'XMLHttpRequest'},
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    await _ensureLoggedIn();
    var resp = await doPost();
    final loc = resp.headers.value('location') ?? '';
    if (loc.toLowerCase().contains('login.php')) {
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      resp = await doPost();
    }
    final raw = resp.data;
    Object? decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        decoded = null;
      }
    }
    if (decoded is! Map) {
      throw ApiException(
          'ITFlow gave an unexpected answer (HTTP ${resp.statusCode}).',
          statusCode: resp.statusCode);
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['status'] == 'error') {
      throw ApiException('${map['message'] ?? 'ITFlow refused the change.'}');
    }
    return map;
  }

  /// Finds the current session's ITFlow user id by searching
  /// `admin/users.php` for [email] (the row's "UserID: N" title attribute is
  /// always rendered, unlike the avatar image which only appears once a user
  /// has uploaded one — there's no dedicated "who am I" endpoint). This also
  /// doubles as the admin-access check the whole provisioning flow needs:
  /// `admin/*` pages call `enforceAdminPermission()`, which bails out with
  /// "Your role does not have admin access." mid-page for anyone else, so a
  /// non-admin account gets a clear [ApiException] here instead of the
  /// silent no-op it'd hit trying to POST `add_api_key` later.
  Future<int> fetchCurrentUserId() async {
    await _ensureLoggedIn();
    final resp = await _dio.get(
      '$_root/admin/users.php',
      queryParameters: {'q': email},
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final body = resp.data?.toString() ?? '';
    if (body.contains('does not have admin access')) {
      throw ApiException(
        'This ITFlow account isn\'t an admin, so it can\'t create API keys. '
        'Ask your admin for a key, or paste one in manually below.',
      );
    }
    final doc = html_parser.parse(body);
    final want = email.toLowerCase();
    for (final row in doc.querySelectorAll('table tbody tr')) {
      // Older builds put the email in a mailto link; newer ones (AdminLTE 4)
      // render it as plain text with a copy button carrying it.
      final emails = <String>{
        for (final a in row.querySelectorAll('a[href^="mailto:"]'))
          a.text.trim().toLowerCase(),
        for (final c in row.querySelectorAll('[data-clipboard-text]'))
          (c.attributes['data-clipboard-text'] ?? '').trim().toLowerCase(),
      };
      if (!emails.contains(want)) continue;
      final title =
          row.querySelector('a[title^="UserID:"]')?.attributes['title'] ?? '';
      final m = RegExp(r'UserID:\s*(\d+)').firstMatch(title);
      if (m != null) return int.parse(m.group(1)!);
      for (final a in row.querySelectorAll('[data-modal-url]')) {
        final m2 = RegExp(
          r'modals/user/user(?:_edit)?\.php\?(?:user_)?id=(\d+)',
        ).firstMatch(a.attributes['data-modal-url'] ?? '');
        if (m2 != null) return int.parse(m2.group(1)!);
      }
    }
    throw ApiException(
      'Could not find an ITFlow user matching "$email" under Admin Settings → Users.',
    );
  }

  /// Creates a new admin-scoped ITFlow API key that runs as the current
  /// session's user (`run_as_user`), so it inherits that user's module
  /// permissions and client access instead of being a separate site-wide
  /// key. Requires the logged-in account to be an ITFlow admin — surfaces a
  /// clear [ApiException] when it isn't (see [fetchCurrentUserId]).
  ///
  /// Returns the new key, its one-time-shown vault decrypt password, and the
  /// row id (needed later to revoke it on rotation).
  Future<CreatedApiKey> createApiKeyForCurrentUser({
    required String name,
    required DateTime expire,
  }) async {
    await _ensureLoggedIn();
    return createApiKey(
        name: name, expire: expire, userId: await fetchCurrentUserId());
  }

  /// The agents an API key can act as, from the "Acts as" picker in Admin >
  /// API Keys > New API Key. Admin only; throws [ApiException] otherwise.
  Future<List<NamedOption>> fetchApiKeyAgents() async {
    final html = await _getModalHtml('admin/modals/api/api_key_add.php');
    if (html.contains('does not have admin access') ||
        (html.contains('name="email"') && html.contains('name="password"'))) {
      throw ApiException(
          'Only an ITFlow admin can make setup codes for other agents.');
    }
    final doc = html_parser.parse(html);
    final out = <NamedOption>[];
    for (final o in doc.querySelectorAll('select[name="run_as_user"] option')) {
      final id = int.tryParse(o.attributes['value'] ?? '');
      if (id == null || id == 0) continue;
      out.add(NamedOption(id: id, name: o.text.trim()));
    }
    if (out.isEmpty) {
      throw ApiException(
          'Only an ITFlow admin can make setup codes for other agents.');
    }
    return out;
  }

  /// Creates an API key acting as agent [userId] (their role and client
  /// access). Admin only.
  Future<CreatedApiKey> createApiKey({
    required String name,
    required DateTime expire,
    required int userId,
  }) async {
    await _ensureLoggedIn();

    Future<Response> getModal() => _dio.get(
      '$_root/admin/modals/api/api_key_add.php',
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    var resp = await getModal();
    var raw = resp.data;
    var bodyStr = raw is String ? raw : (raw?.toString() ?? '');
    if (bodyStr.contains('name="email"') &&
        bodyStr.contains('name="password"')) {
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      resp = await getModal();
      raw = resp.data;
      bodyStr = raw is String ? raw : (raw?.toString() ?? '');
    }

    String htmlContent;
    if (raw is Map && raw['content'] is String) {
      htmlContent = raw['content'] as String;
    } else {
      try {
        final decoded = jsonDecode(bodyStr);
        htmlContent = (decoded is Map && decoded['content'] is String)
            ? decoded['content'] as String
            : bodyStr;
      } catch (_) {
        htmlContent = bodyStr;
      }
    }

    final doc = html_parser.parse(htmlContent);
    String? hidden(String name) =>
        doc.querySelector('input[name="$name"]')?.attributes['value'];
    final csrf = hidden('csrf_token');
    final secret = hidden('key');
    final decryptPassword = hidden('password');
    if (csrf == null || secret == null || decryptPassword == null) {
      throw ApiException(
        'Could not load the "New API Key" form: missing fields.',
      );
    }

    final expireStr =
        '${expire.year.toString().padLeft(4, '0')}-${expire.month.toString().padLeft(2, '0')}-${expire.day.toString().padLeft(2, '0')}';

    final form = FormData.fromMap({
      'csrf_token': csrf,
      'key': secret,
      'password': decryptPassword,
      'name': name,
      'expire': expireStr,
      'run_as_user': userId,
      'ack': '1',
      'add_api_key': '1',
    });
    final postResp = await _dio.post(
      '$_root/admin/post.php',
      data: form,
      options: Options(
        headers: {'Referer': '$_root/admin/api_keys.php'},
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (postResp.statusCode != null && postResp.statusCode! >= 400) {
      throw ApiException(
        'Creating API key failed: HTTP ${postResp.statusCode}',
        statusCode: postResp.statusCode,
      );
    }
    await _raiseOnFlashError(postResp);

    // ITFlow's create handler doesn't echo the new row id, so look it up
    // from the listing page by the (unique) name we just gave it.
    final id = await _findApiKeyIdByName(name);

    return CreatedApiKey(
      id: id,
      secret: secret,
      decryptPassword: decryptPassword,
      userId: userId,
      expiresAt: DateTime(expire.year, expire.month, expire.day),
    );
  }

  Future<int?> _findApiKeyIdByName(String name) async {
    final resp = await _dio.get(
      '$_root/admin/api_keys.php',
      queryParameters: {'q': name},
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final body = resp.data?.toString() ?? '';
    final doc = html_parser.parse(body);
    for (final row in doc.querySelectorAll('table tbody tr')) {
      if (row.text.contains(name)) {
        for (final a in row.querySelectorAll('a')) {
          final m = RegExp(
            r'[?&]id=(\d+)',
          ).firstMatch(a.attributes['data-modal-url'] ?? '');
          if (m != null) return int.tryParse(m.group(1)!);
        }
      }
    }
    return null;
  }

  /// Revokes (immediately expires) an API key the app previously created via
  /// [createApiKeyForCurrentUser]. Best-effort: callers should treat
  /// failures as non-fatal since the local credential has already moved on
  /// to the newly-created key.
  Future<void> revokeApiKey(int apiKeyId) async {
    final csrf = await _getCsrf();
    await _dio.get(
      '$_root/admin/post.php',
      queryParameters: {'revoke_api_key': apiKeyId, 'csrf_token': csrf},
      options: Options(
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
  }

  /// Downloads an invoice PDF from the agent post.php endpoint.
  /// ITFlow validates the CSRF token against the session, so this can't be
  /// constructed as a public URL — it has to be requested by the same
  /// authenticated session that issued the token. Returns raw PDF bytes.
  Future<List<int>> downloadInvoicePdf(int invoiceId) =>
      _downloadPdf('export_invoice_pdf', invoiceId);

  /// Downloads a quote PDF using the same auth dance as [downloadInvoicePdf].
  Future<List<int>> downloadQuotePdf(int quoteId) =>
      _downloadPdf('export_quote_pdf', quoteId);

  Future<List<int>> _downloadPdf(String param, int id) async {
    await _ensureLoggedIn();
    final csrf = await _getCsrf();
    final url = '$_root/agent/post.php?$param=$id&csrf_token=$csrf';
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final loc = resp.headers.value('location') ?? '';
    if (resp.statusCode == 302 &&
        (loc.toLowerCase().contains('login.php') ||
            loc.toLowerCase().endsWith('/index.php'))) {
      // Session/CSRF was rejected — force a re-login and retry once.
      _loggedIn = false;
      _csrfToken = null;
      await _ensureLoggedIn();
      final csrf2 = await _getCsrf();
      final retry = await _dio.get<List<int>>(
        '$_root/agent/post.php?$param=$id&csrf_token=$csrf2',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = retry.data;
      if (data == null || data.isEmpty) {
        throw ApiException('Empty PDF response from server.');
      }
      return data;
    }
    final data = resp.data;
    if (resp.statusCode != 200 || data == null || data.isEmpty) {
      throw ApiException('Failed to download PDF (status ${resp.statusCode}).');
    }
    return data;
  }
}

/// Result of [ItflowWebClient.createApiKeyForCurrentUser].
class CreatedApiKey {
  /// Row id in ITFlow's `api_keys` table. Null if the listing lookup didn't
  /// find it (the key still works — only rotation-time revocation needs this).
  final int? id;
  final String secret;
  final String decryptPassword;
  final int userId;
  final DateTime expiresAt;

  const CreatedApiKey({
    required this.id,
    required this.secret,
    required this.decryptPassword,
    required this.userId,
    required this.expiresAt,
  });
}

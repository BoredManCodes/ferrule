// 2FA sign-in against a fake login.php that answers the way ITFlow's
// develop branch does: the password step renders a pending_mfa_token
// form, a wrong code renders it again with a new token, a right code
// 302s away and sets the rememberme cookie (when remember_me was posted),
// and a valid rememberme cookie on the password step skips 2FA.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ferrule/core/api/api_response.dart';
import 'package:ferrule/core/api/itflow_web_client.dart';
import 'package:ferrule/core/auth/mfa_bridge.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = 'https://itflow.test';

class _FakeStorage extends FlutterSecureStorage {
  final Map<String, String> data = {};
  _FakeStorage();
  @override
  Future<String?> read(
          {required String key,
          AppleOptions? iOptions,
          AndroidOptions? aOptions,
          LinuxOptions? lOptions,
          WebOptions? webOptions,
          AppleOptions? mOptions,
          WindowsOptions? wOptions}) async =>
      data[key];
  @override
  Future<void> write(
      {required String key,
      required String? value,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete(
          {required String key,
          AppleOptions? iOptions,
          AndroidOptions? aOptions,
          LinuxOptions? lOptions,
          WebOptions? webOptions,
          AppleOptions? mOptions,
          WindowsOptions? wOptions}) async =>
      data.remove(key);
  @override
  Future<Map<String, String>> readAll(
          {AppleOptions? iOptions,
          AndroidOptions? aOptions,
          LinuxOptions? lOptions,
          WebOptions? webOptions,
          AppleOptions? mOptions,
          WindowsOptions? wOptions}) async =>
      Map.of(data);
}

class _FakeItflow implements HttpClientAdapter {
  final String code = '123456';
  final Set<String> validRemember = {};
  // One per session, like ITFlow's pending_mfa_login session entry.
  final Set<String> pending = {};
  int passwordPosts = 0;
  int mfaPosts = 0;
  int tokenSeq = 0;

  ResponseBody _html(String body, {int status = 200}) => ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
        },
      );

  ResponseBody _mfaForm({String error = ''}) {
    final t = 'pend${tokenSeq++}';
    pending.add(t);
    return _html('''<html><body>$error<form method="post">
      <input type='text' name='current_code' required autofocus>
      <input type="hidden" name="pending_mfa_token"
             value="$t">
      <input type="checkbox" id="remember_me" name="remember_me">
      <button type="submit" name="mfa_login">Verify & Sign In</button>
      </form></body></html>''');
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final raw = requestStream == null
        ? ''
        : utf8.decode(await requestStream.expand((b) => b).toList());
    // Dio sends FormData as multipart; fall back to urlencoded.
    final form = raw.toLowerCase().contains('content-disposition')
        ? {
            for (final m in RegExp(r'name="([^"]+)"\r\n\r\n(.*?)\r\n')
                .allMatches(raw))
              m.group(1)!: m.group(2)!
          }
        : Uri.splitQueryString(raw);
    final cookie = options.headers['cookie']?.toString() ?? '';
    final rm = RegExp(r'rememberme=([^;]+)').firstMatch(cookie)?.group(1);

    if (form.containsKey('login')) {
      passwordPosts++;
      if (form['password'] != 'pw') return _html('<p>Incorrect</p>');
      if (rm != null && validRemember.contains(rm)) {
        return ResponseBody.fromString('', 302, headers: {
          'location': ['agent/dashboard.php'],
        });
      }
      return _mfaForm();
    }
    if (form.containsKey('mfa_login')) {
      mfaPosts++;
      if (!pending.remove(form['pending_mfa_token'])) {
        return _html('<div>Your MFA session expired.</div>');
      }
      if (form['current_code'] != code) {
        return _mfaForm(error: 'Please enter a valid 2FA code.');
      }
      final headers = <String, List<String>>{
        'location': ['agent/dashboard.php'],
      };
      if (form.containsKey('remember_me')) {
        final t = 'tok${validRemember.length}';
        validRemember.add(t);
        headers['set-cookie'] = [
          'rememberme=$t; expires=Fri, 01-Jan-2100 00:00:00 GMT; '
              'path=/; secure; HttpOnly'
        ];
      }
      return ResponseBody.fromString('', 302, headers: headers);
    }
    return _html('', status: 404);
  }

  @override
  void close({bool force = false}) {}
}

ItflowWebClient _client(_FakeItflow server, {String password = 'pw'}) {
  final dio = Dio()..httpClientAdapter = server;
  return ItflowWebClient(
      baseUrl: _base, email: 'tech@example.com', password: password, dio: dio);
}

void main() {
  late _FakeItflow server;
  late List<String?> promptErrors;
  late List<String?> answers;

  setUp(() {
    server = _FakeItflow();
    MfaBridge.debugUseStorage(_FakeStorage());
    promptErrors = [];
    answers = [];
    MfaBridge.prompt = ({required String email, String? error}) async {
      promptErrors.add(error);
      return answers.isEmpty ? null : answers.removeAt(0);
    };
  });

  test('asks for the code, then the saved cookie skips it', () async {
    answers = ['123456'];
    await _client(server).login();
    expect(promptErrors, [null]);
    expect(await MfaBridge.rememberToken(_base, 'tech@example.com'), 'tok0');

    // A new client (an app restart) signs in with no prompt.
    await _client(server).login();
    expect(promptErrors.length, 1);
    expect(server.mfaPosts, 1);
  });

  test('wrong code re-asks with an error', () async {
    answers = ['000000', '123456'];
    await _client(server).login();
    expect(promptErrors.length, 2);
    expect(promptErrors[1], contains('didn\'t work'));
  });

  test('cancel throws', () async {
    await expectLater(_client(server).login(), throwsA(isA<ApiException>()));
  });

  test('no UI throws a clear error', () async {
    MfaBridge.prompt = null;
    await expectLater(
        _client(server).login(),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', contains('uses 2FA'))));
  });

  test('revoked cookie is dropped and the code asked for again', () async {
    answers = ['123456'];
    await _client(server).login();
    server.validRemember.clear();
    answers = ['123456'];
    await _client(server).login();
    expect(promptErrors.length, 2);
    expect(await MfaBridge.rememberToken(_base, 'tech@example.com'), 'tok0');
  });

  test('parallel logins on one client prompt once', () async {
    answers = ['123456'];
    final c = _client(server);
    await Future.wait([c.login(), c.login(), c.login()]);
    expect(promptErrors.length, 1);
    expect(server.passwordPosts, 1);
  });

  test('two clients racing share one prompt', () async {
    answers = ['123456'];
    await Future.wait([_client(server).login(), _client(server).login()]);
    expect(promptErrors.length, 1);
  });

  test('wrong password still says so', () async {
    await expectLater(
        _client(server, password: 'nope').login(),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', contains('email and password'))));
  });

  test('clearAll forgets tokens', () async {
    answers = ['123456'];
    await _client(server).login();
    await MfaBridge.clearAll();
    expect(await MfaBridge.rememberToken(_base, 'tech@example.com'), isNull);
  });
}

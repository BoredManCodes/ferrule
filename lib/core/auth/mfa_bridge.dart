import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Asks the person for their 2FA code. [error] is set when the last code
/// was rejected. Return null if they cancel.
typedef MfaPrompt = Future<String?> Function({
  required String email,
  String? error,
});

/// Glue between [ItflowWebClient] logins and the app: shows the 2FA prompt
/// and keeps ITFlow's remember-me cookie per instance and email, so a
/// sign-in after the first one skips the code until the cookie expires
/// (ITFlow's "Remember this browser" setting, a few days by default).
class MfaBridge {
  MfaBridge._();

  /// Set by the app once a navigator is up. Null means no UI (tests, a
  /// background isolate), so a login that needs a code fails instead.
  static MfaPrompt? prompt;

  static FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Tokens already read or written this run, so every request doesn't
  /// hit the keystore.
  static final Map<String, String?> _cache = {};

  static Future<void> _lock = Future.value();

  static void debugUseStorage(FlutterSecureStorage storage) {
    _storage = storage;
    _cache.clear();
  }

  static String _key(String baseUrl, String email) {
    final uri = Uri.tryParse(baseUrl);
    final host = '${uri?.host ?? baseUrl}${uri?.path ?? ''}'
        .replaceAll(RegExp(r'/+$'), '');
    return 'mfa_remember:$host:${email.trim().toLowerCase()}';
  }

  static Future<String?> rememberToken(String baseUrl, String email) async {
    final k = _key(baseUrl, email);
    if (_cache.containsKey(k)) return _cache[k];
    String? v;
    try {
      v = await _storage.read(key: k);
    } catch (_) {
      v = null;
    }
    _cache[k] = v;
    return v;
  }

  static Future<void> saveRememberToken(
      String baseUrl, String email, String? token) async {
    final k = _key(baseUrl, email);
    _cache[k] = token;
    try {
      if (token == null || token.isEmpty) {
        await _storage.delete(key: k);
      } else {
        await _storage.write(key: k, value: token);
      }
    } catch (_) {}
  }

  /// Forgets every stored remember-me token (sign out).
  static Future<void> clearAll() async {
    _cache.clear();
    try {
      final all = await _storage.readAll();
      for (final k in all.keys.where((k) => k.startsWith('mfa_remember:'))) {
        await _storage.delete(key: k);
      }
    } catch (_) {}
  }

  /// Runs [f] with no other 2FA prompt on screen, so parallel requests
  /// that all hit a lapsed session ask for one code, not five.
  static Future<T> serialize<T>(Future<T> Function() f) {
    final prev = _lock;
    final done = Completer<void>();
    _lock = done.future;
    return prev.then((_) => f()).whenComplete(done.complete);
  }
}

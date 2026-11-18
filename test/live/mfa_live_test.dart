// 2FA sign-in against a live ITFlow. Needs an account with 2FA on and its
// TOTP secret, so it only runs when one is given:
//   FERRULE_LIVE=1 FERRULE_LIVE_TOTP_SECRET=ABCD... flutter test test/live/mfa_live_test.dart
// Uses FERRULE_LIVE_URL / _EMAIL / _PASSWORD like dev_server_test.dart.
@Tags(['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ferrule/core/api/itflow_web_client.dart';
import 'package:ferrule/core/auth/mfa_bridge.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

final _env = Platform.environment;
final _secret = _env['FERRULE_LIVE_TOTP_SECRET'];
final _run = _env['FERRULE_LIVE'] == '1' && (_secret ?? '').isNotEmpty;
final _url = _env['FERRULE_LIVE_URL'] ?? 'https://develop.dev.itflow.org';
final _email = _env['FERRULE_LIVE_EMAIL'] ?? 'dev@itflow.org';
final _password = _env['FERRULE_LIVE_PASSWORD'] ?? 'dev@itflow.org';

String _totp(String secret, DateTime at) {
  const alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final bits = secret
      .toUpperCase()
      .replaceAll(RegExp(r'[\s=]'), '')
      .split('')
      .map((c) => alpha.indexOf(c).toRadixString(2).padLeft(5, '0'))
      .join();
  final key = [
    for (var i = 0; i + 8 <= bits.length; i += 8)
      int.parse(bits.substring(i, i + 8), radix: 2)
  ];
  final counter = ByteData(8)
    ..setInt64(0, at.millisecondsSinceEpoch ~/ 30000);
  final h = Hmac(sha1, key).convert(counter.buffer.asUint8List()).bytes;
  final o = h[19] & 15;
  final n = ((h[o] & 0x7f) << 24) |
      (h[o + 1] << 16) |
      (h[o + 2] << 8) |
      h[o + 3];
  return (n % 1000000).toString().padLeft(6, '0');
}

/// Keystore stand-in; the real one needs a device.
class _MemStorage extends FlutterSecureStorage {
  final data = <String, String>{};
  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async => data[key];
  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      value == null ? data.remove(key) : data[key] = value;
  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async => data.remove(key);
  @override
  Future<Map<String, String>> readAll({AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async => Map.of(data);
}

void main() {
  final asked = <String?>[];

  setUpAll(() {
    MfaBridge.debugUseStorage(_MemStorage());
    MfaBridge.prompt = ({required String email, String? error}) async {
      asked.add(error);
      // A rejected code means the 30s window rolled over; use the next.
      return _totp(_secret!,
          DateTime.now().add(Duration(seconds: error == null ? 0 : 30)));
    };
  });

  test('wrong code is re-asked, right code signs in', skip: !_run, () async {
    var first = true;
    MfaBridge.prompt = ({required String email, String? error}) async {
      asked.add(error);
      if (first) {
        first = false;
        return '000000';
      }
      return _totp(_secret!, DateTime.now());
    };
    final web = ItflowWebClient(baseUrl: _url, email: _email, password: _password);
    await web.login();
    expect(asked.length, 2);
    expect(asked[1], isNotNull);
    expect(await MfaBridge.rememberToken(_url, _email), isNotNull);
    // Signed in for real: the agent UI hands out a CSRF token.
    final b = await web.fetchInstanceBranding();
    expect(b.accent, isNotNull);
  });

  test('remembered cookie skips the code on a fresh client', skip: !_run,
      () async {
    asked.clear();
    MfaBridge.prompt = ({required String email, String? error}) async {
      asked.add(error);
      return null;
    };
    final web = ItflowWebClient(baseUrl: _url, email: _email, password: _password);
    await web.login();
    expect(asked, isEmpty);
    final b = await web.fetchInstanceBranding();
    expect(b.accent, isNotNull);
  });
}

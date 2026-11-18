import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/itflow_web_client.dart';
import '../storage/secure_store.dart';

/// How long an app-created API key lives before it's rotated.
const apiKeyLifetime = Duration(days: 90);

/// Rotate this long before expiry, so a device that isn't opened for a
/// while still gets a fresh key before the old one stops working.
const _apiKeyRotateBefore = Duration(days: 14);

/// Logs in to the ITFlow web UI with [email]/[password] and creates a new
/// admin-scoped API key that runs as that user (see
/// [ItflowWebClient.createApiKeyForCurrentUser]), instead of requiring the
/// user to paste in a separately-provisioned site-wide key.
///
/// Throws [ApiException] (from `core/api/api_response.dart`, surfaced via
/// [ItflowWebClient]) on login failure or if the account isn't an ITFlow
/// admin.
Future<Credentials> provisionCredentials({
  required String instanceUrl,
  required String email,
  required String password,
}) async {
  final web = ItflowWebClient(
    baseUrl: instanceUrl,
    email: email,
    password: password,
  );
  await web.login();
  final created = await web.createApiKeyForCurrentUser(
    name: _keyName(),
    expire: DateTime.now().add(apiKeyLifetime),
  );
  return Credentials(
    instanceUrl: instanceUrl,
    apiKey: created.secret,
    decryptPassword: created.decryptPassword,
    webEmail: email,
    webPassword: password,
    apiKeyId: created.id,
    apiKeyExpiresAt: created.expiresAt,
    apiKeyManaged: true,
  );
}

/// Checks whether [creds]' API key is app-managed and due for rotation, and
/// if so creates a replacement and revokes the old one. Returns the updated
/// credentials to persist, or null if nothing needed to change.
///
/// Best-effort: any failure (offline, instance unreachable, password
/// changed) is swallowed and null is returned, so the existing key keeps
/// working until it actually expires and the next app launch tries again.
/// Pass [force] to rotate immediately regardless of expiry (a manual
/// "Rotate now" action in Settings); that still lets exceptions through
/// so the UI can report a failure instead of silently doing nothing.
Future<Credentials?> rotateApiKeyIfNeeded(
  Credentials creds, {
  bool force = false,
}) async {
  if (!creds.apiKeyManaged) return null;
  if (!creds.hasWebCreds) return null;
  if (!force) {
    final expiresAt = creds.apiKeyExpiresAt;
    if (expiresAt == null) return null;
    if (DateTime.now().isBefore(expiresAt.subtract(_apiKeyRotateBefore))) {
      return null;
    }
  }

  final web = ItflowWebClient(
    baseUrl: creds.instanceUrl,
    email: creds.webEmail!,
    password: creds.webPassword!,
  );
  try {
    await web.login();
    final created = await web.createApiKeyForCurrentUser(
      name: _keyName(),
      expire: DateTime.now().add(apiKeyLifetime),
    );
    final updated = creds.copyWith(
      apiKey: created.secret,
      decryptPassword: created.decryptPassword,
      apiKeyId: created.id,
      apiKeyExpiresAt: created.expiresAt,
      apiKeyManaged: true,
    );
    final oldId = creds.apiKeyId;
    if (oldId != null) {
      try {
        await web.revokeApiKey(oldId);
      } catch (e) {
        debugPrint('rotateApiKeyIfNeeded: failed to revoke old key: $e');
      }
    }
    return updated;
  } catch (e) {
    debugPrint(
      'rotateApiKeyIfNeeded: rotation failed, keeping existing key: $e',
    );
    if (force) rethrow;
    return null;
  }
}

// Includes time-of-day (not just the date) so two rotations triggered on the
// same day (e.g. testing "Rotate now" twice) still get distinct names -
// _findApiKeyIdByName looks the new key up by name, and a collision with an
// older same-named key could grab the wrong row id.
String _keyName() {
  final now = DateTime.now();
  final stamp =
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}';
  return 'Ferrule ($_platformLabel) - $stamp';
}

String get _platformLabel {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'Android';
    case TargetPlatform.iOS:
      return 'iOS';
    case TargetPlatform.windows:
      return 'Windows';
    case TargetPlatform.macOS:
      return 'macOS';
    case TargetPlatform.linux:
      return 'Linux';
    default:
      return 'App';
  }
}

/// How long a key made for another agent's setup code lasts. Their app
/// can't renew it (only admins can make keys), so it's long, and the app
/// warns them a month before it runs out.
const setupCodeLifetime = Duration(days: 365);

/// Warn this long before a key the app can't renew stops working.
const keyExpiryWarning = Duration(days: 30);

/// What an admin hands a technician so their app can connect without an
/// admin account: the instance, an API key acting as the technician, and
/// that key's vault password. Shown as a QR code; nothing changes on the
/// server beyond the key itself (Admin > API Keys lists it).
class SetupCode {
  static const _prefix = 'ferrule-setup:';

  final String instanceUrl;
  final String apiKey;
  final String decryptPassword;
  final DateTime expiresAt;
  final String agentName;
  final int? apiKeyId;

  const SetupCode({
    required this.instanceUrl,
    required this.apiKey,
    required this.decryptPassword,
    required this.expiresAt,
    required this.agentName,
    this.apiKeyId,
  });

  /// A message to send the technician, with the code in it.
  String shareText() =>
      'Ferrule setup code for $agentName. In the Ferrule app, choose '
      '"I have a setup code", then "Paste code", and paste this whole message. '
      'It signs you in to $instanceUrl until '
      '${expiresAt.toIso8601String().substring(0, 10)}. Do not forward it: '
      'anyone with it can get in as you.\n\n${encode()}';

  String encode() {
    final json = jsonEncode({
      'v': 1,
      'u': instanceUrl,
      'k': apiKey,
      'p': decryptPassword,
      'e': expiresAt.toIso8601String().substring(0, 10),
      'n': agentName,
      if (apiKeyId != null) 'i': apiKeyId,
    });
    return '$_prefix${base64Url.encode(utf8.encode(json))}';
  }

  /// The setup code in [raw] (a QR's text, or a whole pasted message that
  /// contains one), or null when there isn't one.
  static SetupCode? tryParse(String raw) {
    final m = RegExp('${RegExp.escape(_prefix)}[A-Za-z0-9_=-]+').firstMatch(raw);
    if (m == null) return null;
    final t = m.group(0)!;
    try {
      final m = jsonDecode(utf8.decode(
          base64Url.decode(base64Url.normalize(t.substring(_prefix.length)))));
      if (m is! Map || m['v'] != 1) return null;
      final url = m['u'], key = m['k'], pw = m['p'];
      final exp = DateTime.tryParse('${m['e']}');
      if (url is! String || key is! String || pw is! String || exp == null) {
        return null;
      }
      return SetupCode(
        instanceUrl: url,
        apiKey: key,
        decryptPassword: pw,
        expiresAt: exp,
        agentName: '${m['n'] ?? ''}',
        apiKeyId: m['i'] is int ? m['i'] as int : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Credentials for the technician's app. Their own email and password
  /// (optional) unlock the web-only features.
  Credentials toCredentials({String? webEmail, String? webPassword}) =>
      Credentials(
        instanceUrl: instanceUrl,
        apiKey: apiKey,
        decryptPassword: decryptPassword,
        webEmail: (webEmail ?? '').isEmpty ? null : webEmail,
        webPassword: (webPassword ?? '').isEmpty ? null : webPassword,
        apiKeyId: apiKeyId,
        apiKeyExpiresAt: expiresAt,
        apiKeyManaged: false,
      );
}

/// Makes a setup code for [agent] on [creds]' instance, signing in with
/// the admin's web credentials. Throws [ApiException] for non-admins.
Future<SetupCode> createSetupCode(Credentials creds,
    {required int agentId, required String agentName}) async {
  final web = ItflowWebClient(
    baseUrl: creds.instanceUrl,
    email: creds.webEmail!,
    password: creds.webPassword!,
  );
  await web.login();
  final expire = DateTime.now().add(setupCodeLifetime);
  final created = await web.createApiKey(
    name: 'Ferrule setup code - $agentName - ${_keyName().split(' - ').last}',
    expire: expire,
    userId: agentId,
  );
  return SetupCode(
    instanceUrl: creds.instanceUrl,
    apiKey: created.secret,
    decryptPassword: created.decryptPassword,
    expiresAt: created.expiresAt,
    agentName: agentName,
    apiKeyId: created.id,
  );
}

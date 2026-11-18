import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const _instanceUrlKey = 'instance_url';
  static const _apiKeyKey = 'api_key';
  static const _decryptPwKey = 'decrypt_password';
  static const _webEmailKey = 'web_email';
  static const _webPasswordKey = 'web_password';
  static const _apiKeyIdKey = 'api_key_id';
  static const _apiKeyExpiresAtKey = 'api_key_expires_at';
  static const _apiKeyManagedKey = 'api_key_managed';

  final FlutterSecureStorage _storage;

  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<Credentials?> read() async {
    final url = await _storage.read(key: _instanceUrlKey);
    final key = await _storage.read(key: _apiKeyKey);
    final pw = await _storage.read(key: _decryptPwKey);
    final webEmail = await _storage.read(key: _webEmailKey);
    final webPassword = await _storage.read(key: _webPasswordKey);
    final apiKeyId = await _storage.read(key: _apiKeyIdKey);
    final apiKeyExpiresAt = await _storage.read(key: _apiKeyExpiresAtKey);
    final apiKeyManaged = await _storage.read(key: _apiKeyManagedKey);
    if (url == null || url.isEmpty || key == null || key.isEmpty) return null;
    return Credentials(
      instanceUrl: url,
      apiKey: key,
      decryptPassword: pw,
      webEmail: webEmail,
      webPassword: webPassword,
      apiKeyId: apiKeyId == null ? null : int.tryParse(apiKeyId),
      apiKeyExpiresAt:
          apiKeyExpiresAt == null ? null : DateTime.tryParse(apiKeyExpiresAt),
      apiKeyManaged: apiKeyManaged == 'true',
    );
  }

  Future<void> save(Credentials c) async {
    await _storage.write(key: _instanceUrlKey, value: c.instanceUrl);
    await _storage.write(key: _apiKeyKey, value: c.apiKey);
    await _writeOrDelete(_decryptPwKey, c.decryptPassword);
    await _writeOrDelete(_webEmailKey, c.webEmail);
    await _writeOrDelete(_webPasswordKey, c.webPassword);
    await _writeOrDelete(_apiKeyIdKey, c.apiKeyId?.toString());
    await _writeOrDelete(
        _apiKeyExpiresAtKey, c.apiKeyExpiresAt?.toIso8601String());
    await _storage.write(
        key: _apiKeyManagedKey, value: c.apiKeyManaged.toString());
  }

  Future<void> _writeOrDelete(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  Future<void> clear() async {
    for (final k in [
      _instanceUrlKey,
      _apiKeyKey,
      _decryptPwKey,
      _webEmailKey,
      _webPasswordKey,
      _apiKeyIdKey,
      _apiKeyExpiresAtKey,
      _apiKeyManagedKey,
    ]) {
      await _storage.delete(key: k);
    }
  }
}

class Credentials {
  final String instanceUrl;
  final String apiKey;
  final String? decryptPassword;
  final String? webEmail;
  final String? webPassword;

  /// DB id of [apiKey] in ITFlow's `api_keys` table, when the app created it
  /// itself (via [ItflowWebClient.createApiKeyForCurrentUser]). Needed to
  /// revoke the key on rotation. Null for manually-pasted keys.
  final int? apiKeyId;

  /// Expiry the app set when it created [apiKey]. Null for manually-pasted
  /// keys, which are never auto-rotated.
  final DateTime? apiKeyExpiresAt;

  /// True when the app created [apiKey] itself and may rotate/revoke it.
  /// False for a key the user pasted in manually (Advanced setup).
  final bool apiKeyManaged;

  const Credentials({
    required this.instanceUrl,
    required this.apiKey,
    this.decryptPassword,
    this.webEmail,
    this.webPassword,
    this.apiKeyId,
    this.apiKeyExpiresAt,
    this.apiKeyManaged = false,
  });

  bool get hasWebCreds =>
      (webEmail ?? '').isNotEmpty && (webPassword ?? '').isNotEmpty;

  Credentials copyWith({
    String? instanceUrl,
    String? apiKey,
    String? decryptPassword,
    String? webEmail,
    String? webPassword,
    int? apiKeyId,
    DateTime? apiKeyExpiresAt,
    bool? apiKeyManaged,
  }) =>
      Credentials(
        instanceUrl: instanceUrl ?? this.instanceUrl,
        apiKey: apiKey ?? this.apiKey,
        decryptPassword: decryptPassword ?? this.decryptPassword,
        webEmail: webEmail ?? this.webEmail,
        webPassword: webPassword ?? this.webPassword,
        apiKeyId: apiKeyId ?? this.apiKeyId,
        apiKeyExpiresAt: apiKeyExpiresAt ?? this.apiKeyExpiresAt,
        apiKeyManaged: apiKeyManaged ?? this.apiKeyManaged,
      );
}

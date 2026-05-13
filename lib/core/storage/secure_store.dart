import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const _instanceUrlKey = 'instance_url';
  static const _apiKeyKey = 'api_key';
  static const _decryptPwKey = 'decrypt_password';
  static const _webEmailKey = 'web_email';
  static const _webPasswordKey = 'web_password';

  final FlutterSecureStorage _storage;

  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<Credentials?> read() async {
    final url = await _storage.read(key: _instanceUrlKey);
    final key = await _storage.read(key: _apiKeyKey);
    final pw = await _storage.read(key: _decryptPwKey);
    final webEmail = await _storage.read(key: _webEmailKey);
    final webPassword = await _storage.read(key: _webPasswordKey);
    if (url == null || url.isEmpty || key == null || key.isEmpty) return null;
    return Credentials(
      instanceUrl: url,
      apiKey: key,
      decryptPassword: pw,
      webEmail: webEmail,
      webPassword: webPassword,
    );
  }

  Future<void> save(Credentials c) async {
    await _storage.write(key: _instanceUrlKey, value: c.instanceUrl);
    await _storage.write(key: _apiKeyKey, value: c.apiKey);
    await _writeOrDelete(_decryptPwKey, c.decryptPassword);
    await _writeOrDelete(_webEmailKey, c.webEmail);
    await _writeOrDelete(_webPasswordKey, c.webPassword);
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

  const Credentials({
    required this.instanceUrl,
    required this.apiKey,
    this.decryptPassword,
    this.webEmail,
    this.webPassword,
  });

  bool get hasWebCreds =>
      (webEmail ?? '').isNotEmpty && (webPassword ?? '').isNotEmpty;

  Credentials copyWith({
    String? instanceUrl,
    String? apiKey,
    String? decryptPassword,
    String? webEmail,
    String? webPassword,
  }) =>
      Credentials(
        instanceUrl: instanceUrl ?? this.instanceUrl,
        apiKey: apiKey ?? this.apiKey,
        decryptPassword: decryptPassword ?? this.decryptPassword,
        webEmail: webEmail ?? this.webEmail,
        webPassword: webPassword ?? this.webPassword,
      );
}

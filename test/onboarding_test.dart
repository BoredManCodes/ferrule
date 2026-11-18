import 'package:ferrule/core/auth/api_key_provisioning.dart';
import 'package:ferrule/core/settings/ui_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setup code round trip', () {
    final code = SetupCode(
      instanceUrl: 'https://itflow.example.com',
      apiKey: 'abcDEF123_-abcDEF123_-abcDEF1234',
      decryptPassword: 'p@ss/word+',
      expiresAt: DateTime(2027, 11, 18),
      agentName: 'Sam Tech',
      apiKeyId: 9,
    );
    final back = SetupCode.tryParse(code.encode())!;
    expect(back.instanceUrl, code.instanceUrl);
    expect(back.apiKey, code.apiKey);
    expect(back.decryptPassword, code.decryptPassword);
    expect(back.expiresAt, DateTime(2027, 11, 18));
    expect(back.agentName, 'Sam Tech');
    final creds = back.toCredentials(webEmail: '', webPassword: '');
    expect(creds.apiKeyManaged, isFalse);
    expect(creds.hasWebCreds, isFalse);
    expect(creds.apiKeyExpiresAt, DateTime(2027, 11, 18));
  });

  test('setup code found inside a pasted message', () {
    final code = SetupCode(
      instanceUrl: 'https://itflow.example.com',
      apiKey: 'k',
      decryptPassword: 'p',
      expiresAt: DateTime(2027, 1, 2),
      agentName: 'Sam',
    );
    final back = SetupCode.tryParse('Hi Sam!\n\n${code.shareText()}\nThanks');
    expect(back?.agentName, 'Sam');
    expect(back?.apiKey, 'k');
  });

  test('other QR codes are not setup codes', () {
    expect(SetupCode.tryParse('000037_customer_0126'), isNull);
    expect(SetupCode.tryParse('ferrule-setup:not-base64!!'), isNull);
    expect(SetupCode.tryParse('https://example.com'), isNull);
  });

  test('More lists everything off the bar, saved order first', () {
    const p = UiPrefs(
        bar: ['/', '/tickets', '/contacts'],
        more: ['/trips', '/assets', '/gone']);
    final more = p.moreDests.map((d) => d.path).toList();
    expect(more.take(2), ['/trips', '/assets']);
    expect(more, isNot(contains('/contacts')));
    expect(more, isNot(contains('/gone')));
    expect(more.length + p.bar.length, navCatalog.length);
  });
}

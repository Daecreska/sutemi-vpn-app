import 'package:flutter_test/flutter_test.dart';
import 'package:sutemi_vpn/core/network/tunneled_http.dart';
import 'package:sutemi_vpn/core/storage/secure_storage_service.dart';

void main() {
  group('DiagnosticsLogger secret redaction', () {
    test('scrubs UUIDs, reality keys, passwords, userinfo URLs, ss:// base64, and JSON secrets', () {
      const sample =
          'Connecting vless://11111111-2222-3333-4444-555555555555@91.108.56.10:443?pbk=SECRET_PBK&sid=ab12&password=topsecret';
      final redacted = DiagnosticsLogger.redactSecrets(sample);

      expect(redacted.contains('11111111-2222'), isFalse);
      expect(redacted.contains('SECRET_PBK'), isFalse);
      expect(redacted.contains('topsecret'), isFalse);

      const jsonLog = '{"uuid":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","public_key":"PKSECRET","password":"pw"}';
      final redactedJson = DiagnosticsLogger.redactSecrets(jsonLog);
      expect(redactedJson.contains('aaaaaaaa-bbbb'), isFalse);
      expect(redactedJson.contains('PKSECRET'), isFalse);

      const ssUri = 'Importing ss://YWVzLTI1Ni1nY206cGFzc3dvcmRAMTIzLjQ1LjY3Ljg5OjgzODg=#Node';
      final redactedSs = DiagnosticsLogger.redactSecrets(ssUri);
      expect(redactedSs.contains('YWVzLTI1Ni'), isFalse);
      expect(redactedSs.contains('ss://[REDACTED]'), isTrue);
    });
  });

  group('TunneledHttp proxy enforcement', () {
    test('refuses direct fallback when requireVpnProxy is true and proxyPort is invalid', () {
      expect(
        () => TunneledHttp.createClient(proxyPort: null, requireVpnProxy: true),
        throwsA(isA<TunneledHttpException>()),
      );
      expect(
        () => TunneledHttp.createClient(proxyPort: 0, requireVpnProxy: true),
        throwsA(isA<TunneledHttpException>()),
      );
    });
  });
}

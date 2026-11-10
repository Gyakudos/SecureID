import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/services/lan_pairing.dart';

void main() {
  group('PairingLink', () {
    test('round-trips through the QR text', () {
      final link = PairingLink(
        endpoint: Uri.parse('http://192.168.1.20:4567'),
        token: 'one-time-token',
        deviceName: 'Office PC',
      );

      final parsed = PairingLink.tryParse(link.encode());
      expect(parsed, isNotNull);
      expect(parsed!.endpoint.toString(), 'http://192.168.1.20:4567');
      expect(parsed.token, 'one-time-token');
      expect(parsed.deviceName, 'Office PC');
    });

    test('omits an empty device name', () {
      final link = PairingLink(
        endpoint: Uri.parse('http://10.0.0.5:8080'),
        token: 'abc',
      );
      expect(link.encode(), isNot(contains('&n=')));
    });

    test('rejects unrelated codes', () {
      expect(PairingLink.tryParse(''), isNull);
      expect(PairingLink.tryParse('otpauth://totp/x?secret=ABC'), isNull);
      expect(PairingLink.tryParse('https://example.com/pair?t=abc'), isNull);
      expect(
        PairingLink.tryParse('secureid://pair?u=http://10.0.0.2:80'),
        isNull,
      );
      expect(PairingLink.tryParse('secureid://pair?t=abc'), isNull);
      expect(
        PairingLink.tryParse('secureid://pair?u=ftp://10.0.0.2&t=abc'),
        isNull,
      );
    });
  });

  group('LAN pairing', () {
    test('serves the encrypted envelope exactly once', () async {
      final server = LanPairingServer();
      var sent = false;
      const envelope = '{"format":"secureid-vault","payload":"encrypted"}';

      final offer = await server.start(
        readEnvelope: () async => envelope,
        deviceName: 'Test PC',
        bindAddress: InternetAddress.loopbackIPv4,
        addressOverride: '127.0.0.1',
        onSent: () => sent = true,
      );
      addTearDown(server.stop);

      expect(offer.link.deviceName, 'Test PC');
      expect(offer.link.endpoint.host, '127.0.0.1');
      expect(server.isRunning, isTrue);

      final client = LanPairingClient();
      final received = await client.fetchEnvelope(offer.link);
      expect(received, envelope);
      expect(sent, isTrue);
      expect(server.wasUsed, isTrue);

      await expectLater(
        client.fetchEnvelope(offer.link),
        throwsA(isA<PairingException>()),
      );
    });

    test('rejects a wrong token', () async {
      final server = LanPairingServer();
      final offer = await server.start(
        readEnvelope: () async => '{"format":"secureid-vault"}',
        deviceName: 'Test PC',
        bindAddress: InternetAddress.loopbackIPv4,
        addressOverride: '127.0.0.1',
      );
      addTearDown(server.stop);

      final wrong = PairingLink(
        endpoint: offer.link.endpoint,
        token: 'not-the-token',
        deviceName: offer.link.deviceName,
      );
      await expectLater(
        LanPairingClient().fetchEnvelope(wrong),
        throwsA(isA<PairingException>()),
      );
      expect(server.wasUsed, isFalse);
    });

    test('reports an empty vault as a conflict', () async {
      final server = LanPairingServer();
      final offer = await server.start(
        readEnvelope: () async => null,
        deviceName: 'Test PC',
        bindAddress: InternetAddress.loopbackIPv4,
        addressOverride: '127.0.0.1',
      );
      addTearDown(server.stop);

      await expectLater(
        LanPairingClient().fetchEnvelope(offer.link),
        throwsA(
          isA<PairingException>().having(
            (error) => error.message,
            'message',
            contains('no vault'),
          ),
        ),
      );
    });
  });
}

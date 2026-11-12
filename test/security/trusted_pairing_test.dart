import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/security/trusted_pairing.dart';

void main() {
  group('TrustPairingLink', () {
    TrustPairingLink buildLink({List<int>? secret}) => TrustPairingLink(
      endpoint: Uri.parse('http://192.168.1.20:47823'),
      sessionId: 'session-1',
      receiverPublicKey: List<int>.generate(32, (index) => index),
      pairingSecret: secret ?? List<int>.generate(32, (index) => 100 + index),
      deviceId: 'pc-1',
      deviceName: 'Office PC',
      platform: 'windows',
      expiresAt: DateTime.utc(2030, 1, 2, 3, 4),
    );

    test('round-trips through the QR text', () {
      final link = buildLink();
      final parsed = TrustPairingLink.tryParse(link.encode());

      expect(parsed, isNotNull);
      expect(parsed!.endpoint.toString(), 'http://192.168.1.20:47823');
      expect(parsed.sessionId, 'session-1');
      expect(parsed.deviceId, 'pc-1');
      expect(parsed.deviceName, 'Office PC');
      expect(parsed.platform, 'windows');
      expect(parsed.receiverPublicKey, link.receiverPublicKey);
      expect(parsed.pairingSecret, link.pairingSecret);
      expect(parsed.expiresAt, link.expiresAt);
      expect(parsed.displayCode, link.displayCode);
    });

    test('rejects unrelated or incomplete codes', () {
      expect(TrustPairingLink.tryParse(''), isNull);
      expect(TrustPairingLink.tryParse('otpauth://totp/x?secret=ABC'), isNull);
      expect(TrustPairingLink.tryParse('https://example.com/trust'), isNull);
      expect(TrustPairingLink.tryParse('secureid://trust'), isNull);
      expect(
        TrustPairingLink.tryParse(
          'secureid://trust?u=ftp://10.0.0.2&s=a&i=b&k=AA&p=AA&e=1',
        ),
        isNull,
      );
    });

    test('display code is six digits and depends on the session', () {
      final link = buildLink();
      expect(link.displayCode, matches(RegExp(r'^\d{6}$')));

      final other = TrustPairingLink(
        endpoint: link.endpoint,
        sessionId: 'session-2',
        receiverPublicKey: link.receiverPublicKey,
        pairingSecret: link.pairingSecret,
        deviceId: link.deviceId,
        deviceName: link.deviceName,
        platform: link.platform,
        expiresAt: link.expiresAt,
      );
      expect(other.displayCode, isNot(link.displayCode));
    });
  });

  group('pairing keys', () {
    test('both sides derive the same keys and transcript', () async {
      final receiver = await X25519().newKeyPair();
      final sender = await X25519().newKeyPair();
      final receiverPublic = (await receiver.extractPublicKey()).bytes;
      final senderPublic = (await sender.extractPublicKey()).bytes;
      final secret = List<int>.generate(32, (index) => index + 1);

      final receiverKeys = await deriveTrustPairingKeys(
        localKeyPair: receiver,
        remotePublicKey: senderPublic,
        receiverPublicKey: receiverPublic,
        senderPublicKey: senderPublic,
        pairingSecret: secret,
        sessionId: 'session',
        receiverId: 'pc',
        senderId: 'phone',
      );
      final senderKeys = await deriveTrustPairingKeys(
        localKeyPair: sender,
        remotePublicKey: receiverPublic,
        receiverPublicKey: receiverPublic,
        senderPublicKey: senderPublic,
        pairingSecret: secret,
        sessionId: 'session',
        receiverId: 'pc',
        senderId: 'phone',
      );

      expect(receiverKeys.transcript, senderKeys.transcript);
      expect(receiverKeys.trustKey, senderKeys.trustKey);
      expect(receiverKeys.confirmKey, senderKeys.confirmKey);
      expect(receiverKeys.trustKey, hasLength(32));
      expect(receiverKeys.confirmKey, hasLength(32));
      expect(receiverKeys.trustKey, isNot(receiverKeys.confirmKey));

      final proof = await trustHmac(
        receiverKeys.confirmKey,
        'pair|${receiverKeys.transcript}',
      );
      final check = await trustHmac(
        senderKeys.confirmKey,
        'pair|${senderKeys.transcript}',
      );
      expect(constantTimeEquals(proof, check), isTrue);
    });

    test('a different pairing secret produces a different key', () async {
      final receiver = await X25519().newKeyPair();
      final sender = await X25519().newKeyPair();
      final receiverPublic = (await receiver.extractPublicKey()).bytes;
      final senderPublic = (await sender.extractPublicKey()).bytes;

      final first = await deriveTrustPairingKeys(
        localKeyPair: sender,
        remotePublicKey: receiverPublic,
        receiverPublicKey: receiverPublic,
        senderPublicKey: senderPublic,
        pairingSecret: List<int>.filled(32, 1),
        sessionId: 'session',
        receiverId: 'pc',
        senderId: 'phone',
      );
      final second = await deriveTrustPairingKeys(
        localKeyPair: sender,
        remotePublicKey: receiverPublic,
        receiverPublicKey: receiverPublic,
        senderPublicKey: senderPublic,
        pairingSecret: List<int>.filled(32, 2),
        sessionId: 'session',
        receiverId: 'pc',
        senderId: 'phone',
      );

      expect(first.trustKey, isNot(second.trustKey));
    });

    test('rejects keys of the wrong size', () async {
      final receiver = await X25519().newKeyPair();
      final sender = await X25519().newKeyPair();
      final senderPublic = (await sender.extractPublicKey()).bytes;

      await expectLater(
        deriveTrustPairingKeys(
          localKeyPair: receiver,
          remotePublicKey: senderPublic,
          receiverPublicKey: const [1, 2, 3],
          senderPublicKey: senderPublic,
          pairingSecret: List<int>.filled(32, 1),
          sessionId: 'session',
          receiverId: 'pc',
          senderId: 'phone',
        ),
        throwsA(isA<TrustedPairingException>()),
      );
    });
  });

  group('trust payloads', () {
    final key = List<int>.generate(32, (index) => index);

    test('round-trips with the right key and AAD', () async {
      final sealed = await sealTrustPayload(
        key: key,
        plaintext: '{"format":"secureid-vault"}',
        aad: 'transfer-1',
      );
      final opened = await openTrustPayload(
        key: key,
        sealed: sealed,
        aad: 'transfer-1',
      );
      expect(opened, '{"format":"secureid-vault"}');
    });

    test('rejects the wrong key', () async {
      final sealed = await sealTrustPayload(
        key: key,
        plaintext: 'secret',
        aad: 'transfer-1',
      );
      await expectLater(
        openTrustPayload(
          key: List<int>.filled(32, 9),
          sealed: sealed,
          aad: 'transfer-1',
        ),
        throwsA(isA<TrustedPairingException>()),
      );
    });

    test('rejects a changed AAD', () async {
      final sealed = await sealTrustPayload(
        key: key,
        plaintext: 'secret',
        aad: 'transfer-1',
      );
      await expectLater(
        openTrustPayload(key: key, sealed: sealed, aad: 'transfer-2'),
        throwsA(isA<TrustedPairingException>()),
      );
    });
  });

  test('base64 helpers round-trip without padding', () {
    final bytes = List<int>.generate(32, (index) => index * 3);
    final encoded = encodeBytes(bytes);
    expect(encoded, isNot(contains('=')));
    expect(decodeBytes(encoded), bytes);
    expect(decodeBytes(''), isEmpty);
    expect(decodeBytes('not valid!!'), isEmpty);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/trusted_device.dart';
import 'package:secure_id/security/trusted_pairing.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/services/trusted_pairing_transport.dart';

Future<String> buildEnvelope() async {
  final sealed = await VaultCrypto.create(
    password: 'correct horse battery staple',
    plaintext: '{"items":[],"settings":{}}',
    config: VaultKdfConfig.test,
  );
  return sealed.envelope.encode();
}

Future<Map<String, dynamic>> postJson(
  Uri endpoint,
  String path,
  Map<String, dynamic> body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(endpoint.replace(path: path));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final decoded = text.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    return {'status': response.statusCode, ...decoded};
  } finally {
    client.close(force: true);
  }
}

void main() {
  late List<TrustedDevice> remembered;
  late String received;
  late int confirmations;

  Future<TrustedDevice?> find(String id) async {
    for (final device in remembered) {
      if (device.deviceId == id) return device;
    }
    return null;
  }

  Future<void> remember(TrustedDevice device) async {
    remembered = [
      for (final existing in remembered)
        if (existing.deviceId != device.deviceId) existing,
      device,
    ];
  }

  Future<TrustPairingOffer> startReceiver(
    TrustedPairingReceiver receiver, {
    String deviceId = 'pc-1',
  }) {
    return receiver.start(
      deviceId: deviceId,
      deviceName: 'Test PC',
      platform: 'windows',
      findTrusted: find,
      remember: remember,
      onConfirm: (device, pairing) async {
        confirmations++;
        return true;
      },
      onEnvelope: (envelope, sender) async {
        received = envelope;
        return true;
      },
      bindAddress: InternetAddress.loopbackIPv4,
      addressOverride: '127.0.0.1',
      port: 0,
      broadcast: false,
    );
  }

  setUp(() {
    remembered = [];
    received = '';
    confirmations = 0;
  });

  test('pairs and pushes a vault in one scan', () async {
    final envelope = await buildEnvelope();
    final receiver = TrustedPairingReceiver();
    addTearDown(receiver.stop);
    final offer = await startReceiver(receiver);
    final sender = TrustedPairingSender(timeout: const Duration(seconds: 10));

    final device = await sender.pairAndPush(
      link: offer.link,
      senderId: 'phone-1',
      senderName: 'Test Phone',
      senderPlatform: 'android',
      envelope: envelope,
    );

    expect(device.deviceId, 'pc-1');
    expect(device.trustKey, hasLength(32));
    expect(received, envelope);
    expect(remembered, hasLength(1));
    expect(remembered.single.deviceId, 'phone-1');
    // The sender does not listen while pushing, so the remembered address uses
    // the receiver's stable port, not the ephemeral one this test bound.
    expect(remembered.single.lastAddress, '127.0.0.1:$kTrustedReceiverPort');
    expect(confirmations, 1);
    expect(receiver.wasUsed, isTrue);

    // A used pairing code cannot be replayed.
    await expectLater(
      sender.pairAndPush(
        link: offer.link,
        senderId: 'phone-1',
        senderName: 'Test Phone',
        senderPlatform: 'android',
        envelope: envelope,
      ),
      throwsA(isA<TrustedTransferException>()),
    );
  });

  test('sends again to an already trusted device', () async {
    final envelope = await buildEnvelope();
    final receiver = TrustedPairingReceiver();
    addTearDown(receiver.stop);
    final offer = await startReceiver(receiver);
    final sender = TrustedPairingSender(timeout: const Duration(seconds: 10));

    final device = await sender.pairAndPush(
      link: offer.link,
      senderId: 'phone-1',
      senderName: 'Test Phone',
      senderPlatform: 'android',
      envelope: envelope,
    );

    received = '';
    final updated = await sender.sendToTrusted(
      device: device,
      senderId: 'phone-1',
      senderName: 'Test Phone',
      senderPlatform: 'android',
      envelope: envelope,
      endpoint: offer.link.endpoint,
    );

    expect(received, envelope);
    expect(updated.deviceId, 'pc-1');
    // One confirmation for pairing, one for the later transfer.
    expect(confirmations, 2);
  });

  test('auto-accept skips the later confirmation', () async {
    final envelope = await buildEnvelope();
    final receiver = TrustedPairingReceiver();
    addTearDown(receiver.stop);
    final offer = await startReceiver(receiver);
    final sender = TrustedPairingSender(timeout: const Duration(seconds: 10));

    final device = await sender.pairAndPush(
      link: offer.link,
      senderId: 'phone-1',
      senderName: 'Test Phone',
      senderPlatform: 'android',
      envelope: envelope,
    );
    await remember(remembered.single.copyWith(autoAccept: true));

    await sender.sendToTrusted(
      device: device,
      senderId: 'phone-1',
      senderName: 'Test Phone',
      senderPlatform: 'android',
      envelope: envelope,
      endpoint: offer.link.endpoint,
    );

    expect(confirmations, 1);
  });

  test('rejects a wrong pairing secret', () async {
    final envelope = await buildEnvelope();
    final receiver = TrustedPairingReceiver();
    addTearDown(receiver.stop);
    final offer = await startReceiver(receiver);
    final sender = TrustedPairingSender(timeout: const Duration(seconds: 10));

    final tampered = TrustPairingLink(
      endpoint: offer.link.endpoint,
      sessionId: offer.link.sessionId,
      receiverPublicKey: offer.link.receiverPublicKey,
      pairingSecret: List<int>.filled(32, 7),
      deviceId: offer.link.deviceId,
      deviceName: offer.link.deviceName,
      platform: offer.link.platform,
      expiresAt: offer.link.expiresAt,
    );

    await expectLater(
      sender.pairAndPush(
        link: tampered,
        senderId: 'phone-1',
        senderName: 'Test Phone',
        senderPlatform: 'android',
        envelope: envelope,
      ),
      throwsA(isA<TrustedTransferException>()),
    );
    expect(received, isEmpty);
  });

  test('rejects an expired pairing code before using the network', () async {
    final envelope = await buildEnvelope();
    final sender = TrustedPairingSender();
    final expired = TrustPairingLink(
      endpoint: Uri.parse('http://127.0.0.1:1'),
      sessionId: 'session',
      receiverPublicKey: List<int>.filled(32, 1),
      pairingSecret: List<int>.filled(32, 2),
      deviceId: 'pc-1',
      deviceName: 'Test PC',
      platform: 'windows',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    await expectLater(
      sender.pairAndPush(
        link: expired,
        senderId: 'phone-1',
        senderName: 'Test Phone',
        senderPlatform: 'android',
        envelope: envelope,
      ),
      throwsA(isA<TrustedTransferException>()),
    );
  });

  test('rejects something that is not a vault', () async {
    final receiver = TrustedPairingReceiver();
    addTearDown(receiver.stop);
    final offer = await startReceiver(receiver);

    await expectLater(
      TrustedPairingSender().pairAndPush(
        link: offer.link,
        senderId: 'phone-1',
        senderName: 'Test Phone',
        senderPlatform: 'android',
        envelope: '{"format":"other"}',
      ),
      throwsA(isA<TrustedTransferException>()),
    );
  });

  test('a trusted push token can only be used once', () async {
    final envelope = await buildEnvelope();
    final receiver = TrustedPairingReceiver();
    addTearDown(receiver.stop);
    final offer = await startReceiver(receiver);
    final sender = TrustedPairingSender(timeout: const Duration(seconds: 10));

    await sender.pairAndPush(
      link: offer.link,
      senderId: 'phone-1',
      senderName: 'Test Phone',
      senderPlatform: 'android',
      envelope: envelope,
    );
    final trusted = remembered.single;
    received = '';

    final hello = await postJson(offer.link.endpoint, '/trusted/hello', {
      'senderId': 'phone-1',
      'senderNonce': 'nonce-1',
    });
    expect(hello['status'], HttpStatus.ok);
    final receiverNonce = hello['receiverNonce'] as String;

    final proof = await trustHmac(
      trusted.trustKey,
      'hello|phone-1|pc-1|nonce-1|$receiverNonce',
    );
    final verify = await postJson(offer.link.endpoint, '/trusted/verify', {
      'senderId': 'phone-1',
      'senderNonce': 'nonce-1',
      'proof': encodeBytes(proof),
    });
    expect(verify['status'], HttpStatus.ok);
    final token = verify['token'] as String;

    final sealed = await sealTrustPayload(
      key: trusted.trustKey,
      plaintext: envelope,
      aad: 'secureid-trust-push-v1|trusted|phone-1|pc-1|$token',
    );
    final push = {'senderId': 'phone-1', 'token': token, 'sealed': sealed};

    final first = await postJson(offer.link.endpoint, '/trusted/push', push);
    expect(first['status'], HttpStatus.ok);
    expect(received, envelope);

    final replay = await postJson(offer.link.endpoint, '/trusted/push', push);
    expect(replay['status'], HttpStatus.unauthorized);
  });

  test('an unknown device cannot start a trusted transfer', () async {
    final receiver = TrustedPairingReceiver();
    addTearDown(receiver.stop);
    final offer = await startReceiver(receiver);

    final hello = await postJson(offer.link.endpoint, '/trusted/hello', {
      'senderId': 'stranger',
      'senderNonce': 'nonce-1',
    });
    expect(hello['status'], HttpStatus.notFound);
  });

  group('LAN discovery', () {
    test('reads a typed ip or ip:port', () {
      expect(
        parseLanEndpoint('192.168.1.20')?.toString(),
        'http://192.168.1.20:$kTrustedReceiverPort',
      );
      expect(
        parseLanEndpoint(' 192.168.1.20:47900/ ')?.toString(),
        'http://192.168.1.20:47900',
      );
      expect(
        parseLanEndpoint('http://10.0.0.5:47830')?.toString(),
        'http://10.0.0.5:47830',
      );
      expect(
        parseLanEndpoint('localhost')?.toString(),
        'http://127.0.0.1:$kTrustedReceiverPort',
      );
      expect(parseLanEndpoint(''), isNull);
      expect(parseLanEndpoint('not an address'), isNull);
      expect(parseLanEndpoint('192.168.1.20:0'), isNull);
      expect(parseLanEndpoint('192.168.1.20:99999'), isNull);
      expect(parseLanEndpoint('https://192.168.1.20'), isNull);
      expect(parseLanEndpoint('::1'), isNull);
    });

    test('falls back to the next stable port when one is busy', () async {
      HttpServer? blocker;
      try {
        blocker = await HttpServer.bind(
          InternetAddress.anyIPv4,
          kTrustedReceiverPort,
        );
      } on SocketException {
        // Something else already owns the port; the fallback still applies.
      }
      final receiver = TrustedPairingReceiver();
      addTearDown(() async {
        await receiver.stop();
        await blocker?.close(force: true);
      });

      await receiver.start(
        deviceId: 'pc-1',
        deviceName: 'Test PC',
        platform: 'windows',
        findTrusted: find,
        remember: remember,
        onEnvelope: (envelope, sender) async => true,
        bindAddress: InternetAddress.loopbackIPv4,
        addressOverride: '127.0.0.1',
        broadcast: false,
      );

      expect(kTrustedReceiverPorts, contains(receiver.port));
      if (blocker != null) {
        expect(receiver.port, isNot(kTrustedReceiverPort));
      }
    });

    test('answers a unicast probe with its address and port', () async {
      const discoveryPort = 47991;
      final receiver = TrustedPairingReceiver();
      addTearDown(receiver.stop);
      final offer = await receiver.start(
        deviceId: 'pc-1',
        deviceName: 'Test PC',
        platform: 'windows',
        findTrusted: find,
        remember: remember,
        onEnvelope: (envelope, sender) async => true,
        bindAddress: InternetAddress.anyIPv4,
        addressOverride: '127.0.0.1',
        port: 0,
        discoveryPort: discoveryPort,
      );

      final sender = TrustedPairingSender(
        discoveryPort: discoveryPort,
        timeout: const Duration(seconds: 5),
      );
      final found = await sender.discover(
        timeout: const Duration(seconds: 3),
        deviceIds: {'pc-1'},
        addresses: {'127.0.0.1'},
      );

      expect(found, hasLength(1));
      expect(found.single.deviceId, 'pc-1');
      expect(found.single.address, isNotEmpty);
      expect(found.single.port, offer.link.endpoint.port);
    });

    test(
      'rediscovers a receiver when the remembered address is stale',
      () async {
        const discoveryPort = 47992;
        final envelope = await buildEnvelope();
        final receiver = TrustedPairingReceiver();
        addTearDown(receiver.stop);
        final offer = await receiver.start(
          deviceId: 'pc-1',
          deviceName: 'Test PC',
          platform: 'windows',
          findTrusted: find,
          remember: remember,
          onEnvelope: (envelope, sender) async {
            received = envelope;
            return true;
          },
          onConfirm: (device, pairing) async {
            confirmations++;
            return true;
          },
          bindAddress: InternetAddress.anyIPv4,
          addressOverride: '127.0.0.1',
          port: 0,
          discoveryPort: discoveryPort,
        );

        final sender = TrustedPairingSender(
          discoveryPort: discoveryPort,
          timeout: const Duration(seconds: 10),
        );
        final paired = await sender.pairAndPush(
          link: offer.link,
          senderId: 'phone-1',
          senderName: 'Test Phone',
          senderPlatform: 'android',
          envelope: envelope,
        );
        received = '';

        final updated = await sender.sendToTrusted(
          device: paired.copyWith(lastAddress: '127.0.0.1:1'),
          senderId: 'phone-1',
          senderName: 'Test Phone',
          senderPlatform: 'android',
          envelope: envelope,
        );

        expect(received, envelope);
        expect(updated.lastAddress, endsWith(':${offer.link.endpoint.port}'));
      },
    );
  });
}

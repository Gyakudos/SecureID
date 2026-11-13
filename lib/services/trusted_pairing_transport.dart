import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../models/trusted_device.dart';
import '../security/trusted_pairing.dart';
import '../security/vault_crypto.dart';
import '../util/ids.dart';
import 'lan_pairing.dart';

/// Default UDP port used to announce a receiving device on the LAN.
const int kTrustedDiscoveryPort = 47823;

/// Preferred TCP port for receiving trusted transfers.
///
/// A stable port keeps the remembered `host:port` valid between sessions, so a
/// later transfer works even when UDP discovery is blocked. If the port is
/// busy, the receiver falls back to an ephemeral one.
const int kTrustedReceiverPort = 47824;

/// A trusted device seen on the local network.
class DiscoveredTrustedDevice {
  const DiscoveredTrustedDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
  });

  final String deviceId;
  final String name;
  final String platform;
  final String address;
  final int port;

  Uri get endpoint => Uri.parse('http://$address:$port');
}

/// Raised when a trusted transfer cannot be started, reached or completed.
class TrustedTransferException implements Exception {
  const TrustedTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PendingPair {
  const _PendingPair({
    required this.sender,
    required this.token,
    required this.expiresAt,
  });

  final TrustedDevice sender;
  final String token;
  final DateTime expiresAt;
}

class _Challenge {
  const _Challenge({
    required this.senderNonce,
    required this.receiverNonce,
    required this.expiresAt,
  });

  final String senderNonce;
  final String receiverNonce;
  final DateTime expiresAt;
}

class _PushToken {
  const _PushToken({required this.senderId, required this.expiresAt});

  final String senderId;
  final DateTime expiresAt;
}

/// Serves a one-time pairing QR and accepts pushes from trusted devices.
///
/// The receiver never decrypts the vault. It only unwraps the transport
/// envelope with a trust key and hands the already-encrypted vault to
/// [onEnvelope].
class TrustedPairingReceiver {
  TrustedPairingReceiver({
    this.ttl = const Duration(minutes: 5),
    this.challengeTtl = const Duration(minutes: 2),
    this.maxBodyBytes = 32 * 1024 * 1024,
    this.maxFailures = 6,
    this.failureWindow = const Duration(minutes: 1),
  });

  final Duration ttl;
  final Duration challengeTtl;
  final int maxBodyBytes;
  final int maxFailures;
  final Duration failureWindow;

  HttpServer? _server;
  RawDatagramSocket? _beacon;
  Timer? _beaconTimer;
  Timer? _expiryTimer;
  SimpleKeyPair? _keyPair;
  TrustPairingOffer? _offer;
  String _deviceId = '';
  String _deviceName = '';
  String _devicePlatform = '';
  String _address = '';
  bool _used = false;

  final Map<String, _PendingPair> _pendingPairs = {};
  final Map<String, _Challenge> _challenges = {};
  final Map<String, _PushToken> _pushTokens = {};
  final Map<String, List<DateTime>> _failures = {};

  Future<TrustedDevice?> Function(String deviceId)? _findTrusted;
  Future<void> Function(TrustedDevice device)? _remember;
  Future<bool> Function(TrustedDevice sender, bool pairing)? _onConfirm;
  Future<bool> Function(String envelope, TrustedDevice sender)? _onEnvelope;

  bool get isRunning => _server != null;
  bool get wasUsed => _used;
  TrustPairingOffer? get offer => _offer;
  int? get port => _server?.port;

  /// Starts the receiver and returns the QR offer.
  ///
  /// [port] and [broadcast] are mainly for tests; production prefers a stable
  /// TCP port and announces it over UDP.
  Future<TrustPairingOffer> start({
    required String deviceId,
    required String deviceName,
    required String platform,
    required Future<TrustedDevice?> Function(String deviceId) findTrusted,
    required Future<void> Function(TrustedDevice device) remember,
    required Future<bool> Function(String envelope, TrustedDevice sender)
    onEnvelope,
    Future<bool> Function(TrustedDevice sender, bool pairing)? onConfirm,
    InternetAddress? bindAddress,
    String? addressOverride,
    int? port,
    int discoveryPort = kTrustedDiscoveryPort,
    bool broadcast = true,
  }) async {
    await stop();

    final address = addressOverride ?? await pickLanAddress();
    if (address == null) {
      throw const TrustedTransferException(
        'No local network address was found. Connect this device to Wi-Fi or '
        'a LAN and try again.',
      );
    }

    final server = await _bindServer(
      bindAddress ?? InternetAddress.anyIPv4,
      port,
    );
    final keyPair = await X25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final sessionId = newId(16);
    final secret = newPairingSecret();
    final expiresAt = DateTime.now().add(ttl);

    _server = server;
    _keyPair = keyPair;
    _deviceId = deviceId;
    _deviceName = deviceName;
    _devicePlatform = platform;
    _address = address;
    _used = false;
    _findTrusted = findTrusted;
    _remember = remember;
    _onConfirm = onConfirm;
    _onEnvelope = onEnvelope;
    _pendingPairs.clear();
    _challenges.clear();
    _pushTokens.clear();
    _failures.clear();

    _offer = TrustPairingOffer(
      link: TrustPairingLink(
        endpoint: Uri.parse('http://$address:${server.port}'),
        sessionId: sessionId,
        receiverPublicKey: publicKey.bytes,
        pairingSecret: secret,
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
        expiresAt: expiresAt,
      ),
      address: address,
      expiresAt: expiresAt,
    );

    server.listen(_handle, onError: (Object _) {});
    _expiryTimer = Timer(ttl, () => unawaited(stop()));
    if (broadcast) {
      unawaited(_startBeacon(discoveryPort, server.port));
    }
    return _offer!;
  }

  Future<HttpServer> _bindServer(
    InternetAddress address,
    int? requestedPort,
  ) async {
    if (requestedPort != null) {
      return HttpServer.bind(address, requestedPort);
    }
    try {
      return await HttpServer.bind(address, kTrustedReceiverPort);
    } on SocketException {
      return HttpServer.bind(address, 0);
    }
  }

  Future<void> _startBeacon(int discoveryPort, int serverPort) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _beacon = socket;

      void announce() {
        final offer = _offer;
        if (offer == null) return;
        final payload = utf8.encode(
          jsonEncode({
            'app': 'SecureID',
            'version': 1,
            'id': _deviceId,
            'name': _deviceName,
            'platform': _devicePlatform,
            'port': serverPort,
            'pairing': !_used,
          }),
        );
        try {
          socket.send(
            payload,
            InternetAddress('255.255.255.255'),
            discoveryPort,
          );
        } catch (_) {
          // Some networks block broadcast; the QR and last address still work.
        }
      }

      announce();
      _beaconTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => announce(),
      );
    } catch (_) {
      // Discovery is best-effort. Pairing by QR and the remembered address
      // still work when UDP broadcast is unavailable.
    }
  }

  Future<void> stop() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    final beacon = _beacon;
    _beacon = null;
    beacon?.close();

    final server = _server;
    _server = null;
    _offer = null;
    _keyPair = null;
    _findTrusted = null;
    _remember = null;
    _onConfirm = null;
    _onEnvelope = null;
    _pendingPairs.clear();
    _challenges.clear();
    _pushTokens.clear();
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    try {
      if (request.method == 'GET' && request.uri.path == '/health') {
        await _writeJson(response, HttpStatus.ok, {
          'app': 'SecureID',
          'version': 1,
          'id': _deviceId,
          'device': _deviceName,
          'platform': _devicePlatform,
          'trusted': true,
        });
        return;
      }
      if (request.method != 'POST') {
        await _writeJson(response, HttpStatus.methodNotAllowed, {
          'error': 'Only POST is allowed.',
        });
        return;
      }

      final body = await _readBody(request);
      if (body == null) {
        await _writeJson(response, HttpStatus.requestEntityTooLarge, {
          'error': 'The transfer is too large.',
        });
        return;
      }
      Map<String, dynamic> json;
      try {
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException();
        }
        json = decoded;
      } on FormatException {
        await _writeJson(response, HttpStatus.badRequest, {
          'error': 'The request was not valid JSON.',
        });
        return;
      }

      final ip = request.connectionInfo?.remoteAddress.address ?? '';
      if (_isBlocked(ip)) {
        await _writeJson(response, HttpStatus.tooManyRequests, {
          'error': 'Too many failed attempts. Wait a minute and try again.',
        });
        return;
      }

      switch (request.uri.path) {
        case '/pair':
          await _handlePair(json, request, response, ip);
        case '/push':
          await _handlePairPush(json, request, response, ip);
        case '/trusted/hello':
          await _handleHello(json, response, ip);
        case '/trusted/verify':
          await _handleVerify(json, response, ip);
        case '/trusted/push':
          await _handleTrustedPush(json, request, response, ip);
        default:
          await _writeJson(response, HttpStatus.notFound, {
            'error': 'Unknown endpoint.',
          });
      }
    } catch (_) {
      try {
        await _writeJson(response, HttpStatus.internalServerError, {
          'error': 'The receiving device could not finish the transfer.',
        });
      } catch (_) {
        // The connection is already gone.
      }
    } finally {
      await response.close();
    }
  }

  Future<String?> _readBody(HttpRequest request) async {
    if (request.contentLength > maxBodyBytes) return null;
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxBodyBytes) return null;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> _handlePair(
    Map<String, dynamic> json,
    HttpRequest request,
    HttpResponse response,
    String ip,
  ) async {
    final offer = _offer;
    final keyPair = _keyPair;
    if (offer == null || keyPair == null) {
      await _writeJson(response, HttpStatus.gone, {
        'error': 'This pairing code has expired.',
      });
      return;
    }
    if (_used) {
      await _writeJson(response, HttpStatus.gone, {
        'error': 'This pairing code was already used.',
      });
      return;
    }
    if (DateTime.now().isAfter(offer.expiresAt)) {
      await _writeJson(response, HttpStatus.gone, {
        'error': 'This pairing code has expired.',
      });
      return;
    }

    final sessionId = json['session'] as String? ?? '';
    final senderId = json['senderId'] as String? ?? '';
    final senderName = (json['senderName'] as String? ?? '').trim();
    final senderPlatform = json['senderPlatform'] as String? ?? 'unknown';
    final senderPublicKey = decodeBytes(json['publicKey'] as String? ?? '');
    final proof = decodeBytes(json['proof'] as String? ?? '');

    if (sessionId != offer.link.sessionId ||
        senderId.isEmpty ||
        senderId == _deviceId ||
        senderPublicKey.length != 32 ||
        proof.isEmpty) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.badRequest, {
        'error': 'The pairing request was incomplete.',
      });
      return;
    }

    final receiverPublicKey = offer.link.receiverPublicKey;
    final TrustPairingKeys keys;
    try {
      keys = await deriveTrustPairingKeys(
        localKeyPair: keyPair,
        remotePublicKey: senderPublicKey,
        receiverPublicKey: receiverPublicKey,
        senderPublicKey: senderPublicKey,
        pairingSecret: offer.link.pairingSecret,
        sessionId: sessionId,
        receiverId: _deviceId,
        senderId: senderId,
      );
    } catch (exception) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.badRequest, {
        'error': exception is TrustedPairingException
            ? exception.message
            : 'The pairing keys could not be derived.',
      });
      return;
    }

    final expected = await trustHmac(
      keys.confirmKey,
      'pair|${keys.transcript}',
    );
    if (!constantTimeEquals(expected, proof)) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.unauthorized, {
        'error': 'The pairing confirmation did not match.',
      });
      return;
    }

    _clearFailures(ip);
    final sender = TrustedDevice(
      deviceId: senderId,
      name: senderName.isEmpty ? 'SecureID phone' : senderName,
      platform: senderPlatform,
      trustKey: keys.trustKey,
      createdAt: DateTime.now(),
      lastUsedAt: DateTime.now(),
      lastAddress: _requestAddress(request),
    );
    final token = newId(24);
    _pendingPairs[sessionId] = _PendingPair(
      sender: sender,
      token: token,
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );

    final acceptProof = await trustHmac(
      keys.confirmKey,
      'accept|${keys.transcript}',
    );
    await _writeJson(response, HttpStatus.ok, {
      'ok': true,
      'receiverId': _deviceId,
      'receiverName': _deviceName,
      'receiverPlatform': _devicePlatform,
      'proof': encodeBytes(acceptProof),
      'pushToken': token,
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 2))
          .toUtc()
          .millisecondsSinceEpoch,
    });
  }

  Future<void> _handlePairPush(
    Map<String, dynamic> json,
    HttpRequest request,
    HttpResponse response,
    String ip,
  ) async {
    final sessionId = json['session'] as String? ?? '';
    final token = json['token'] as String? ?? '';
    final senderId = json['senderId'] as String? ?? '';
    final sealed = json['sealed'] as String? ?? '';

    final pending = _pendingPairs[sessionId];
    if (pending == null ||
        DateTime.now().isAfter(pending.expiresAt) ||
        pending.token != token ||
        pending.sender.deviceId != senderId ||
        sealed.isEmpty) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.gone, {
        'error': 'The pairing request expired. Show a new code.',
      });
      return;
    }

    final aad = 'secureid-trust-push-v1|$sessionId|$senderId|$_deviceId';
    final String envelope;
    try {
      envelope = await openTrustPayload(
        key: pending.sender.trustKey,
        sealed: sealed,
        aad: aad,
      );
    } on TrustedPairingException catch (exception) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.unauthorized, {
        'error': exception.message,
      });
      return;
    }

    if (!_isVaultEnvelope(envelope)) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.badRequest, {
        'error': 'The other device did not send a SecureID vault.',
      });
      return;
    }

    final confirmed = await _confirm(pending.sender, pairing: true);
    if (!confirmed) {
      _pendingPairs.remove(sessionId);
      await _writeJson(response, HttpStatus.forbidden, {
        'error': 'The receiving device declined the transfer.',
      });
      return;
    }

    final accepted = await _onEnvelope?.call(envelope, pending.sender) ?? false;
    if (!accepted) {
      _pendingPairs.remove(sessionId);
      await _writeJson(response, HttpStatus.conflict, {
        'error': 'The receiving device could not store the vault.',
      });
      return;
    }

    _pendingPairs.remove(sessionId);
    _used = true;
    _clearFailures(ip);
    try {
      await _remember?.call(pending.sender);
    } catch (_) {
      // The vault was already imported; a stale trust record is recoverable.
    }
    await _writeJson(response, HttpStatus.ok, {'ok': true});
  }

  Future<void> _handleHello(
    Map<String, dynamic> json,
    HttpResponse response,
    String ip,
  ) async {
    final senderId = json['senderId'] as String? ?? '';
    final senderNonce = json['senderNonce'] as String? ?? '';
    if (senderId.isEmpty || senderNonce.isEmpty) {
      await _writeJson(response, HttpStatus.badRequest, {
        'error': 'The discovery request was incomplete.',
      });
      return;
    }
    final device = await _findTrusted?.call(senderId);
    if (device == null) {
      await _writeJson(response, HttpStatus.notFound, {
        'error': 'This device is not trusted. Scan a new pairing code.',
      });
      return;
    }

    final receiverNonce = newId(16);
    _challenges[senderId] = _Challenge(
      senderNonce: senderNonce,
      receiverNonce: receiverNonce,
      expiresAt: DateTime.now().add(challengeTtl),
    );
    await _writeJson(response, HttpStatus.ok, {
      'ok': true,
      'receiverId': _deviceId,
      'receiverNonce': receiverNonce,
      'expiresAt': DateTime.now()
          .add(challengeTtl)
          .toUtc()
          .millisecondsSinceEpoch,
    });
  }

  Future<void> _handleVerify(
    Map<String, dynamic> json,
    HttpResponse response,
    String ip,
  ) async {
    final senderId = json['senderId'] as String? ?? '';
    final senderNonce = json['senderNonce'] as String? ?? '';
    final proof = decodeBytes(json['proof'] as String? ?? '');
    final challenge = _challenges.remove(senderId);
    if (challenge == null ||
        DateTime.now().isAfter(challenge.expiresAt) ||
        challenge.senderNonce != senderNonce ||
        proof.isEmpty) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.unauthorized, {
        'error': 'The trusted-device challenge expired. Try again.',
      });
      return;
    }

    final device = await _findTrusted?.call(senderId);
    if (device == null) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.notFound, {
        'error': 'This device is not trusted any more.',
      });
      return;
    }

    final expected = await trustHmac(
      device.trustKey,
      'hello|$senderId|$_deviceId|$senderNonce|${challenge.receiverNonce}',
    );
    if (!constantTimeEquals(expected, proof)) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.unauthorized, {
        'error': 'The trusted-device proof did not match.',
      });
      return;
    }

    final confirmed = device.autoAccept
        ? true
        : await _confirm(device, pairing: false);
    if (!confirmed) {
      await _writeJson(response, HttpStatus.forbidden, {
        'error': 'The receiving device declined the transfer.',
      });
      return;
    }

    _clearFailures(ip);
    final token = newId(24);
    _pushTokens[token] = _PushToken(
      senderId: senderId,
      expiresAt: DateTime.now().add(challengeTtl),
    );
    await _writeJson(response, HttpStatus.ok, {
      'ok': true,
      'token': token,
      'expiresAt': DateTime.now()
          .add(challengeTtl)
          .toUtc()
          .millisecondsSinceEpoch,
    });
  }

  Future<void> _handleTrustedPush(
    Map<String, dynamic> json,
    HttpRequest request,
    HttpResponse response,
    String ip,
  ) async {
    final senderId = json['senderId'] as String? ?? '';
    final token = json['token'] as String? ?? '';
    final sealed = json['sealed'] as String? ?? '';
    final entry = _pushTokens.remove(token);
    if (entry == null ||
        entry.senderId != senderId ||
        DateTime.now().isAfter(entry.expiresAt) ||
        sealed.isEmpty) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.unauthorized, {
        'error': 'The trusted transfer expired. Try again.',
      });
      return;
    }

    final device = await _findTrusted?.call(senderId);
    if (device == null) {
      await _writeJson(response, HttpStatus.notFound, {
        'error': 'This device is not trusted any more.',
      });
      return;
    }

    final aad = 'secureid-trust-push-v1|trusted|$senderId|$_deviceId|$token';
    final String envelope;
    try {
      envelope = await openTrustPayload(
        key: device.trustKey,
        sealed: sealed,
        aad: aad,
      );
    } on TrustedPairingException catch (exception) {
      _recordFailure(ip);
      await _writeJson(response, HttpStatus.unauthorized, {
        'error': exception.message,
      });
      return;
    }

    if (!_isVaultEnvelope(envelope)) {
      await _writeJson(response, HttpStatus.badRequest, {
        'error': 'The other device did not send a SecureID vault.',
      });
      return;
    }

    final accepted = await _onEnvelope?.call(envelope, device) ?? false;
    if (!accepted) {
      await _writeJson(response, HttpStatus.conflict, {
        'error': 'The receiving device could not store the vault.',
      });
      return;
    }

    _clearFailures(ip);
    try {
      await _remember?.call(
        device.copyWith(
          lastUsedAt: DateTime.now(),
          lastAddress: _requestAddress(request),
        ),
      );
    } catch (_) {
      // A stale address is harmless; the next transfer can rediscover it.
    }
    await _writeJson(response, HttpStatus.ok, {'ok': true});
  }

  Future<bool> _confirm(TrustedDevice sender, {required bool pairing}) async {
    final callback = _onConfirm;
    if (callback == null) return !pairing;
    return callback(sender, pairing);
  }

  String _requestAddress(HttpRequest request) {
    final ip = request.connectionInfo?.remoteAddress.address ?? '';
    if (ip.isEmpty) return _address;
    // The sender does not listen while pushing, so remember the stable port
    // its receiver prefers. Discovery can still correct this when the port is
    // busy and the other device falls back to an ephemeral one.
    return '$ip:$kTrustedReceiverPort';
  }

  bool _isVaultEnvelope(String envelope) {
    try {
      VaultEnvelope.decode(envelope);
      return true;
    } on FormatException {
      return false;
    }
  }

  bool _isBlocked(String ip) {
    if (ip.isEmpty) return false;
    final entries = _failures[ip];
    if (entries == null) return false;
    final cutoff = DateTime.now().subtract(failureWindow);
    entries.removeWhere((time) => time.isBefore(cutoff));
    return entries.length >= maxFailures;
  }

  void _recordFailure(String ip) {
    if (ip.isEmpty) return;
    final entries = _failures.putIfAbsent(ip, () => []);
    entries.add(DateTime.now());
  }

  void _clearFailures(String ip) {
    _failures.remove(ip);
  }

  Future<void> _writeJson(
    HttpResponse response,
    int status,
    Map<String, dynamic> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }
}

/// Sends the encrypted vault to a paired device.
class TrustedPairingSender {
  TrustedPairingSender({
    this.timeout = const Duration(seconds: 15),
    this.confirmTimeout = const Duration(seconds: 90),
    this.discoveryPort = kTrustedDiscoveryPort,
  });

  final Duration timeout;

  /// How long to wait while the receiving device asks its user to confirm.
  final Duration confirmTimeout;
  final int discoveryPort;

  /// Completes the first pairing and pushes the vault in one scan.
  Future<TrustedDevice> pairAndPush({
    required TrustPairingLink link,
    required String senderId,
    required String senderName,
    required String senderPlatform,
    required String envelope,
  }) async {
    if (DateTime.now().isAfter(link.expiresAt.toLocal())) {
      throw const TrustedTransferException(
        'That pairing code has expired. Show a new code on the other device.',
      );
    }
    if (!_looksLikeVault(envelope)) {
      throw const TrustedTransferException('There is no vault to send yet.');
    }

    final keyPair = await X25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final keys = await deriveTrustPairingKeys(
      localKeyPair: keyPair,
      remotePublicKey: link.receiverPublicKey,
      receiverPublicKey: link.receiverPublicKey,
      senderPublicKey: publicKey.bytes,
      pairingSecret: link.pairingSecret,
      sessionId: link.sessionId,
      receiverId: link.deviceId,
      senderId: senderId,
    );

    final pairProof = await trustHmac(
      keys.confirmKey,
      'pair|${keys.transcript}',
    );
    final pairResponse = await _postJson(link.endpoint.replace(path: '/pair'), {
      'session': link.sessionId,
      'senderId': senderId,
      'senderName': senderName,
      'senderPlatform': senderPlatform,
      'publicKey': encodeBytes(publicKey.bytes),
      'proof': encodeBytes(pairProof),
    });

    final receiverId = pairResponse['receiverId'] as String? ?? '';
    final receiverName = (pairResponse['receiverName'] as String? ?? '').trim();
    final receiverPlatform =
        pairResponse['receiverPlatform'] as String? ?? 'unknown';
    final acceptProof = decodeBytes(pairResponse['proof'] as String? ?? '');
    final pushToken = pairResponse['pushToken'] as String? ?? '';
    if (receiverId.isEmpty ||
        receiverId != link.deviceId ||
        acceptProof.isEmpty ||
        pushToken.isEmpty) {
      throw const TrustedTransferException(
        'The other device did not finish pairing.',
      );
    }

    final expected = await trustHmac(
      keys.confirmKey,
      'accept|${keys.transcript}',
    );
    if (!constantTimeEquals(expected, acceptProof)) {
      throw const TrustedTransferException(
        'The pairing confirmation did not match. Show a new code and try again.',
      );
    }

    final sealed = await sealTrustPayload(
      key: keys.trustKey,
      plaintext: envelope,
      aad: 'secureid-trust-push-v1|${link.sessionId}|$senderId|$receiverId',
    );
    await _postJson(link.endpoint.replace(path: '/push'), {
      'session': link.sessionId,
      'token': pushToken,
      'senderId': senderId,
      'sealed': sealed,
    }, responseTimeout: confirmTimeout);

    final now = DateTime.now();
    return TrustedDevice(
      deviceId: receiverId,
      name: receiverName.isEmpty ? 'SecureID PC' : receiverName,
      platform: receiverPlatform,
      trustKey: keys.trustKey,
      createdAt: now,
      lastUsedAt: now,
      lastAddress: link.endpoint.authority,
    );
  }

  /// Pushes to an already paired device after a challenge-response check.
  Future<TrustedDevice> sendToTrusted({
    required TrustedDevice device,
    required String senderId,
    required String senderName,
    required String senderPlatform,
    required String envelope,
    Uri? endpoint,
  }) async {
    if (!_looksLikeVault(envelope)) {
      throw const TrustedTransferException('There is no vault to send yet.');
    }

    final target = endpoint ?? _endpointFor(device);
    if (target == null) {
      throw const TrustedTransferException(
        'The other device has not been seen yet. Open Receive on it, then try '
        'again.',
      );
    }

    final senderNonce = newId(16);
    final hello = await _postJson(target.replace(path: '/trusted/hello'), {
      'senderId': senderId,
      'senderNonce': senderNonce,
    });
    final receiverId = hello['receiverId'] as String? ?? '';
    final receiverNonce = hello['receiverNonce'] as String? ?? '';
    if (receiverId.isEmpty || receiverId != device.deviceId) {
      throw const TrustedTransferException(
        'The other device is not the one you paired with.',
      );
    }

    final proof = await trustHmac(
      device.trustKey,
      'hello|$senderId|$receiverId|$senderNonce|$receiverNonce',
    );
    final verify = await _postJson(target.replace(path: '/trusted/verify'), {
      'senderId': senderId,
      'senderNonce': senderNonce,
      'proof': encodeBytes(proof),
    }, responseTimeout: confirmTimeout);
    final token = verify['token'] as String? ?? '';
    if (token.isEmpty) {
      throw const TrustedTransferException(
        'The other device did not approve the transfer.',
      );
    }

    final sealed = await sealTrustPayload(
      key: device.trustKey,
      plaintext: envelope,
      aad: 'secureid-trust-push-v1|trusted|$senderId|$receiverId|$token',
    );
    await _postJson(target.replace(path: '/trusted/push'), {
      'senderId': senderId,
      'token': token,
      'sealed': sealed,
    });

    return device.copyWith(
      lastUsedAt: DateTime.now(),
      lastAddress: target.authority,
    );
  }

  /// Listens for receiving devices on the LAN for [timeout].
  Future<List<DiscoveredTrustedDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
    Set<String>? deviceIds,
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      final found = <String, DiscoveredTrustedDevice>{};
      final done = Completer<void>();

      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket?.receive();
          if (datagram == null) return;
          try {
            final decoded = jsonDecode(utf8.decode(datagram.data));
            if (decoded is! Map<String, dynamic>) return;
            if (decoded['app'] != 'SecureID') return;
            final id = decoded['id'] as String? ?? '';
            final port = (decoded['port'] as num?)?.toInt() ?? 0;
            if (id.isEmpty || port <= 0) return;
            if (deviceIds != null && !deviceIds.contains(id)) return;
            found[id] = DiscoveredTrustedDevice(
              deviceId: id,
              name: decoded['name'] as String? ?? 'SecureID device',
              platform: decoded['platform'] as String? ?? 'unknown',
              address: datagram.address.address,
              port: port,
            );
          } catch (_) {
            // Ignore unrelated broadcast traffic.
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
      );

      await Future.any([done.future, Future<void>.delayed(timeout)]);
      return found.values.toList(growable: false);
    } catch (_) {
      return const [];
    } finally {
      socket?.close();
    }
  }

  Uri? _endpointFor(TrustedDevice device) {
    final address = device.lastAddress;
    if (address == null || address.trim().isEmpty) return null;
    final uri = Uri.tryParse('http://$address');
    if (uri == null || uri.host.isEmpty || uri.port <= 0) return null;
    return uri;
  }

  bool _looksLikeVault(String envelope) {
    if (envelope.trim().isEmpty) return false;
    try {
      VaultEnvelope.decode(envelope);
      return true;
    } on FormatException {
      return false;
    }
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? responseTimeout,
  }) async {
    final wait = responseTimeout ?? timeout;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(wait);
      final text = await response.transform(utf8.decoder).join().timeout(wait);

      Map<String, dynamic> json = const {};
      if (text.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic>) json = decoded;
        } on FormatException {
          // The status code below decides whether that matters.
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TrustedTransferException(
          json['error'] as String? ??
              'The other device refused the transfer '
                  '(${response.statusCode}).',
        );
      }
      return json;
    } on TrustedTransferException {
      rethrow;
    } on TimeoutException {
      throw const TrustedTransferException(
        'The other device did not respond. Make sure both devices are on the '
        'same Wi-Fi and try again.',
      );
    } on SocketException {
      throw const TrustedTransferException(
        'Could not reach the other device. Check that both devices are on the '
        'same Wi-Fi and that the firewall allows the connection.',
      );
    } catch (error) {
      throw TrustedTransferException('Could not finish the transfer: $error');
    } finally {
      client.close(force: true);
    }
  }
}

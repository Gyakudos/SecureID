import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../util/ids.dart';

/// Raised when a trusted pairing step fails or a code is not a trust link.
class TrustedPairingException implements Exception {
  const TrustedPairingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The public offer a receiving device shows as a QR code.
///
/// The pairing secret travels only through the QR image. It is mixed into the
/// key derivation, so an attacker who sees the X25519 public keys on the
/// network still cannot derive the trust key.
class TrustPairingLink {
  const TrustPairingLink({
    required this.endpoint,
    required this.sessionId,
    required this.receiverPublicKey,
    required this.pairingSecret,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.expiresAt,
  });

  final Uri endpoint;
  final String sessionId;
  final List<int> receiverPublicKey;
  final List<int> pairingSecret;
  final String deviceId;
  final String deviceName;
  final String platform;
  final DateTime expiresAt;

  /// Six digits shown on the receiving device and on the scanning phone so a
  /// replaced QR code is visible before anything is sent.
  String get displayCode => trustDisplayCode(sessionId, pairingSecret);

  Uri toUri() => Uri(
    scheme: 'secureid',
    host: 'trust',
    queryParameters: {
      'u': endpoint.toString(),
      's': sessionId,
      'k': encodeBytes(receiverPublicKey),
      'p': encodeBytes(pairingSecret),
      'i': deviceId,
      'n': deviceName,
      'pl': platform,
      'e': expiresAt.toUtc().millisecondsSinceEpoch.toString(),
    },
  );

  String encode() => toUri().toString();

  /// Parses a scanned `secureid://trust?...` code.
  static TrustPairingLink? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'secureid' || uri.host != 'trust') {
      return null;
    }
    final query = uri.queryParameters;
    final endpoint = Uri.tryParse(query['u'] ?? '');
    if (endpoint == null ||
        endpoint.scheme != 'http' ||
        endpoint.host.isEmpty) {
      return null;
    }
    final sessionId = query['s'] ?? '';
    final deviceId = query['i'] ?? '';
    final receiverKey = decodeBytes(query['k'] ?? '');
    final secret = decodeBytes(query['p'] ?? '');
    final expiry = int.tryParse(query['e'] ?? '');
    if (sessionId.isEmpty ||
        deviceId.isEmpty ||
        receiverKey.length != 32 ||
        secret.length != 32 ||
        expiry == null) {
      return null;
    }
    return TrustPairingLink(
      endpoint: endpoint,
      sessionId: sessionId,
      receiverPublicKey: receiverKey,
      pairingSecret: secret,
      deviceId: deviceId,
      deviceName: (query['n'] ?? '').trim().isEmpty
          ? 'SecureID device'
          : query['n']!,
      platform: query['pl'] ?? 'unknown',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiry, isUtc: true),
    );
  }
}

/// A running pairing offer, with the local address to display.
class TrustPairingOffer {
  const TrustPairingOffer({
    required this.link,
    required this.address,
    required this.expiresAt,
  });

  final TrustPairingLink link;
  final String address;
  final DateTime expiresAt;

  String get code => link.displayCode;
}

/// The keys derived from one successful X25519 exchange.
class TrustPairingKeys {
  const TrustPairingKeys({
    required this.trustKey,
    required this.confirmKey,
    required this.transcript,
  });

  /// Authenticates later transfers. It can never decrypt the vault.
  final List<int> trustKey;

  /// Authenticates the pairing handshake itself.
  final List<int> confirmKey;

  /// Canonical text both sides HMAC to prove they derived the same keys.
  final String transcript;
}

/// Builds the canonical transcript for a pairing exchange.
///
/// Both devices must pass the same device order: receiver first, sender second.
String trustTranscript({
  required String sessionId,
  required String receiverId,
  required String senderId,
  required List<int> receiverPublicKey,
  required List<int> senderPublicKey,
}) {
  return [
    'secureid-trust-v1',
    sessionId,
    receiverId,
    senderId,
    encodeBytes(receiverPublicKey),
    encodeBytes(senderPublicKey),
  ].join('|');
}

/// Derives the trust and confirmation keys for one pairing session.
///
/// [receiverPublicKey] and [senderPublicKey] must name the same keys on both
/// devices, in the same order, even though each device holds a different
/// private key. [localKeyPair] is paired with [remotePublicKey] for the ECDH
/// step.
Future<TrustPairingKeys> deriveTrustPairingKeys({
  required SimpleKeyPair localKeyPair,
  required List<int> remotePublicKey,
  required List<int> receiverPublicKey,
  required List<int> senderPublicKey,
  required List<int> pairingSecret,
  required String sessionId,
  required String receiverId,
  required String senderId,
}) async {
  if (remotePublicKey.length != 32 ||
      receiverPublicKey.length != 32 ||
      senderPublicKey.length != 32) {
    throw const TrustedPairingException(
      'The other device sent an invalid key.',
    );
  }
  if (pairingSecret.length != 32) {
    throw const TrustedPairingException('The pairing secret is invalid.');
  }

  final shared = await X25519().sharedSecretKey(
    keyPair: localKeyPair,
    remotePublicKey: SimplePublicKey(remotePublicKey, type: KeyPairType.x25519),
  );

  final transcript = trustTranscript(
    sessionId: sessionId,
    receiverId: receiverId,
    senderId: senderId,
    receiverPublicKey: receiverPublicKey,
    senderPublicKey: senderPublicKey,
  );

  final trustKey = await _derive(
    shared: shared,
    salt: pairingSecret,
    info: 'secureid-trust-key-v1|$transcript',
  );
  final confirmKey = await _derive(
    shared: shared,
    salt: pairingSecret,
    info: 'secureid-trust-confirm-v1|$transcript',
  );

  return TrustPairingKeys(
    trustKey: trustKey,
    confirmKey: confirmKey,
    transcript: transcript,
  );
}

Future<List<int>> _derive({
  required SecretKey shared,
  required List<int> salt,
  required String info,
}) async {
  final derived = await Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: shared, nonce: salt, info: utf8.encode(info));
  return derived.bytes;
}

/// Computes an HMAC-SHA256 and returns the raw bytes.
Future<List<int>> trustHmac(List<int> key, String message) async {
  final mac = await Hmac.sha256().calculateMac(
    utf8.encode(message),
    secretKey: SecretKey(key),
  );
  return mac.bytes;
}

/// Constant-time comparison for MACs and tokens.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var index = 0; index < a.length; index++) {
    difference |= a[index] ^ b[index];
  }
  return difference == 0;
}

/// Seals a payload with AES-256-GCM using [key] and [aad].
Future<String> sealTrustPayload({
  required List<int> key,
  required String plaintext,
  required String aad,
}) async {
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(plaintext),
    secretKey: SecretKey(key),
    aad: utf8.encode(aad),
  );
  return encodeBytes(box.concatenation());
}

/// Opens a payload sealed by [sealTrustPayload].
Future<String> openTrustPayload({
  required List<int> key,
  required String sealed,
  required String aad,
}) async {
  try {
    final box = SecretBox.fromConcatenation(
      decodeBytes(sealed),
      nonceLength: 12,
      macLength: 16,
    );
    final clear = await AesGcm.with256bits().decrypt(
      box,
      secretKey: SecretKey(key),
      aad: utf8.encode(aad),
    );
    return utf8.decode(clear);
  } catch (_) {
    throw const TrustedPairingException(
      'The encrypted transfer could not be opened. The pairing key may not '
      'match.',
    );
  }
}

/// A short human-checkable code for a pairing session.
String trustDisplayCode(String sessionId, List<int> pairingSecret) {
  final digest = crypto.Hmac(
    crypto.sha256,
    pairingSecret,
  ).convert(utf8.encode('secureid-trust-code-v1|$sessionId'));
  final value =
      (digest.bytes[0] << 24 |
          digest.bytes[1] << 16 |
          digest.bytes[2] << 8 |
          digest.bytes[3]) &
      0x7fffffff;
  return (value % 1000000).toString().padLeft(6, '0');
}

/// URL-safe base64 without padding, used inside QR codes and JSON.
String encodeBytes(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

/// Decodes [encodeBytes] output, returning an empty list on bad input.
List<int> decodeBytes(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  try {
    final padded = trimmed.padRight((trimmed.length + 3) & ~3, '=');
    return base64Url.decode(padded);
  } on FormatException {
    return const [];
  }
}

/// Generates a random 32-byte pairing secret.
List<int> newPairingSecret() => randomBytes(32);

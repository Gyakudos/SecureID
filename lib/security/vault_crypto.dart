import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../util/ids.dart';

/// Argon2id parameters used when creating a new vault.
class VaultKdfConfig {
  const VaultKdfConfig({
    this.memory = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  /// 1 KiB blocks. 19456 = 19 MiB, the OWASP recommendation.
  final int memory;
  final int iterations;
  final int parallelism;

  /// Fast parameters for unit tests only. Never use this for a real vault.
  static const VaultKdfConfig test = VaultKdfConfig(
    memory: 64,
    iterations: 1,
    parallelism: 1,
  );
}

/// The unencrypted envelope written to disk.
///
/// It contains only the KDF parameters, salt and ciphertext. The master
/// password and every vault secret stay out of the file.
class VaultEnvelope {
  const VaultEnvelope({
    required this.salt,
    required this.payload,
    required this.memory,
    required this.iterations,
    required this.parallelism,
    this.hashLength = VaultCrypto.keyLength,
  });

  final List<int> salt;
  final List<int> payload;
  final int memory;
  final int iterations;
  final int parallelism;
  final int hashLength;

  /// Stable identifier for this vault. Devices that share a vault id share the
  /// same salt, so the same master password derives the same key.
  String get vaultId => base64Encode(salt);

  VaultEnvelope copyWithPayload(List<int> nextPayload) => VaultEnvelope(
    salt: salt,
    payload: nextPayload,
    memory: memory,
    iterations: iterations,
    parallelism: parallelism,
    hashLength: hashLength,
  );

  String encode() => jsonEncode({
    'format': 'secureid-vault',
    'version': VaultCrypto.formatVersion,
    'kdf': {
      'algorithm': 'argon2id',
      'salt': base64Encode(salt),
      'memory': memory,
      'iterations': iterations,
      'parallelism': parallelism,
      'hashLength': hashLength,
    },
    'cipher': {
      'algorithm': 'aes-256-gcm',
      'nonceLength': VaultCrypto.nonceLength,
      'payload': base64Encode(payload),
    },
  });

  factory VaultEnvelope.decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The vault envelope is not a JSON object.');
    }
    if (decoded['format'] != 'secureid-vault') {
      throw const FormatException('Not a SecureID vault file.');
    }
    if (decoded['version'] != VaultCrypto.formatVersion) {
      throw const FormatException('Unsupported vault format version.');
    }
    final kdf = decoded['kdf'];
    final cipher = decoded['cipher'];
    if (kdf is! Map || cipher is! Map) {
      throw const FormatException('The vault envelope is incomplete.');
    }
    if (kdf['algorithm'] != 'argon2id' ||
        cipher['algorithm'] != 'aes-256-gcm') {
      throw const FormatException('Unsupported vault algorithms.');
    }
    final salt = base64Decode(kdf['salt'] as String? ?? '');
    final payload = base64Decode(cipher['payload'] as String? ?? '');
    final memory = (kdf['memory'] as num?)?.toInt() ?? 0;
    final iterations = (kdf['iterations'] as num?)?.toInt() ?? 0;
    final parallelism = (kdf['parallelism'] as num?)?.toInt() ?? 0;
    final hashLength =
        (kdf['hashLength'] as num?)?.toInt() ?? VaultCrypto.keyLength;
    if (salt.length < 16 ||
        payload.length < VaultCrypto.nonceLength + VaultCrypto.macLength ||
        memory < 8 ||
        iterations < 1 ||
        parallelism < 1 ||
        hashLength != VaultCrypto.keyLength) {
      throw const FormatException('The vault envelope has invalid parameters.');
    }
    return VaultEnvelope(
      salt: salt,
      payload: payload,
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength,
    );
  }
}

/// Argon2id key derivation plus AES-256-GCM authenticated encryption.
class VaultCrypto {
  const VaultCrypto._();

  static const int formatVersion = 1;
  static const int keyLength = 32;
  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int macLength = 16;
  static const String _aad = 'secureid-vault-v1';

  static final AesGcm _cipher = AesGcm.with256bits();

  static Future<SecretKey> deriveKey(
    String password,
    List<int> salt,
    VaultKdfConfig config,
  ) {
    final algorithm = Argon2id(
      parallelism: config.parallelism,
      memory: config.memory,
      iterations: config.iterations,
      hashLength: keyLength,
    );
    return algorithm.deriveKeyFromPassword(password: password, nonce: salt);
  }

  /// Returns nonce + ciphertext + MAC.
  static Future<List<int>> encrypt(SecretKey key, String plaintext) async {
    final box = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      aad: utf8.encode(_aad),
    );
    return box.concatenation();
  }

  static Future<String> decrypt(SecretKey key, List<int> payload) async {
    final box = SecretBox.fromConcatenation(
      payload,
      nonceLength: nonceLength,
      macLength: macLength,
    );
    final clear = await _cipher.decrypt(
      box,
      secretKey: key,
      aad: utf8.encode(_aad),
    );
    return utf8.decode(clear);
  }

  /// Creates a brand new vault envelope and returns the derived key so the
  /// caller can keep it in memory for later saves without re-running Argon2.
  static Future<({VaultEnvelope envelope, SecretKey key})> create({
    required String password,
    required String plaintext,
    VaultKdfConfig config = const VaultKdfConfig(),
  }) async {
    final salt = randomBytes(saltLength);
    final key = await deriveKey(password, salt, config);
    final payload = await encrypt(key, plaintext);
    return (
      envelope: VaultEnvelope(
        salt: salt,
        payload: payload,
        memory: config.memory,
        iterations: config.iterations,
        parallelism: config.parallelism,
      ),
      key: key,
    );
  }
}

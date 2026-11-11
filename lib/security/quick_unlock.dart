import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/device_login.dart';
import '../util/ids.dart';
import 'vault_crypto.dart';

/// Argon2id parameters for the PIN/pattern quick-unlock record.
///
/// A six-digit PIN has little entropy, so the derivation is deliberately more
/// expensive than the vault KDF. The in-app attempt limit is the second line of
/// defence, and the master password is always the fallback.
class QuickUnlockConfig {
  const QuickUnlockConfig({
    this.memory = 65536,
    this.iterations = 3,
    this.parallelism = 1,
  });

  /// 1 KiB blocks. 65536 = 64 MiB.
  final int memory;
  final int iterations;
  final int parallelism;

  /// Fast parameters for unit tests only. Never use these on a device.
  static const QuickUnlockConfig test = QuickUnlockConfig(
    memory: 64,
    iterations: 1,
    parallelism: 1,
  );
}

/// The local record that lets a PIN or pattern unwrap the vault key.
class QuickUnlockRecord {
  const QuickUnlockRecord({
    required this.vaultId,
    required this.style,
    required this.salt,
    required this.wrappedKey,
    required this.config,
    this.failedAttempts = 0,
  });

  /// Base64 of the vault's KDF salt, used to bind this record to one vault.
  final String vaultId;
  final PasswordStyle style;

  /// Argon2id salt for the PIN/pattern.
  final List<int> salt;

  /// AES-GCM nonce + ciphertext + MAC of the vault key.
  final List<int> wrappedKey;

  final QuickUnlockConfig config;
  final int failedAttempts;

  QuickUnlockRecord copyWith({int? failedAttempts}) => QuickUnlockRecord(
    vaultId: vaultId,
    style: style,
    salt: salt,
    wrappedKey: wrappedKey,
    config: config,
    failedAttempts: failedAttempts ?? this.failedAttempts,
  );

  String encode() => jsonEncode({
    'format': 'secureid-quick',
    'version': 1,
    'vaultId': vaultId,
    'style': style.name,
    'kdf': {
      'algorithm': 'argon2id',
      'salt': base64Encode(salt),
      'memory': config.memory,
      'iterations': config.iterations,
      'parallelism': config.parallelism,
    },
    'wrappedKey': base64Encode(wrappedKey),
    'failedAttempts': failedAttempts,
  });

  factory QuickUnlockRecord.decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'secureid-quick' ||
        decoded['version'] != 1) {
      throw const FormatException('Not a SecureID quick-unlock record.');
    }
    final vaultId = decoded['vaultId'] as String? ?? '';
    final saltText = (decoded['kdf'] as Map?)?['salt'] as String? ?? '';
    final wrappedText = decoded['wrappedKey'] as String? ?? '';
    final style = PasswordStyle.values.firstWhere(
      (value) => value.name == decoded['style'],
      orElse: () => PasswordStyle.pin,
    );
    final kdf = decoded['kdf'];
    final memory = (kdf is Map ? (kdf['memory'] as num?)?.toInt() : null) ?? 0;
    final iterations =
        (kdf is Map ? (kdf['iterations'] as num?)?.toInt() : null) ?? 0;
    final parallelism =
        (kdf is Map ? (kdf['parallelism'] as num?)?.toInt() : null) ?? 0;
    final salt = base64Decode(saltText);
    final wrappedKey = base64Decode(wrappedText);
    if (vaultId.isEmpty ||
        salt.length < 16 ||
        wrappedKey.length < VaultCrypto.nonceLength + VaultCrypto.macLength ||
        memory < 8 ||
        iterations < 1 ||
        parallelism < 1) {
      throw const FormatException('The quick-unlock record is incomplete.');
    }
    return QuickUnlockRecord(
      vaultId: vaultId,
      style: style,
      salt: salt,
      wrappedKey: wrappedKey,
      config: QuickUnlockConfig(
        memory: memory,
        iterations: iterations,
        parallelism: parallelism,
      ),
      failedAttempts: (decoded['failedAttempts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Wraps and unwraps the vault key with a PIN or pattern.
class QuickUnlockCrypto {
  const QuickUnlockCrypto._();

  static const int maxAttempts = 5;
  static const int pinLength = 6;
  static const int patternMinDots = 4;
  static const String _aad = 'secureid-quick-v1';

  static final AesGcm _cipher = AesGcm.with256bits();

  /// Builds the canonical secret string for a drawn pattern.
  static String patternSecret(List<int> dots) => dots.join('-');

  static bool isValidPin(String pin) =>
      pin.length == pinLength && RegExp(r'^\d{6}$').hasMatch(pin);

  static bool isValidPattern(List<int> dots) {
    if (dots.length < patternMinDots || dots.length > 9) return false;
    if (dots.any((dot) => dot < 0 || dot > 8)) return false;
    return dots.toSet().length == dots.length;
  }

  static Future<QuickUnlockRecord> create({
    required List<int> vaultKey,
    required List<int> vaultSalt,
    required PasswordStyle style,
    required String secret,
    QuickUnlockConfig config = const QuickUnlockConfig(),
  }) async {
    final salt = randomBytes(VaultCrypto.saltLength);
    final key = await _derive(secret, salt, config);
    final box = await _cipher.encrypt(
      vaultKey,
      secretKey: key,
      aad: utf8.encode(_aad),
    );
    return QuickUnlockRecord(
      vaultId: base64Encode(vaultSalt),
      style: style,
      salt: salt,
      wrappedKey: box.concatenation(),
      config: config,
    );
  }

  /// Returns the vault key, or throws [SecretBoxAuthenticationError] when the
  /// secret is wrong.
  static Future<List<int>> unlock(
    QuickUnlockRecord record,
    String secret,
  ) async {
    final key = await _derive(secret, record.salt, record.config);
    final box = SecretBox.fromConcatenation(
      record.wrappedKey,
      nonceLength: VaultCrypto.nonceLength,
      macLength: VaultCrypto.macLength,
    );
    return _cipher.decrypt(box, secretKey: key, aad: utf8.encode(_aad));
  }

  static Future<SecretKey> _derive(
    String secret,
    List<int> salt,
    QuickUnlockConfig config,
  ) {
    final algorithm = Argon2id(
      parallelism: config.parallelism,
      memory: config.memory,
      iterations: config.iterations,
      hashLength: VaultCrypto.keyLength,
    );
    return algorithm.deriveKeyFromPassword(password: secret, nonce: salt);
  }

  /// Clears the key material once it is no longer needed.
  static void wipe(Uint8List? bytes) {
    bytes?.fillRange(0, bytes.length, 0);
  }
}

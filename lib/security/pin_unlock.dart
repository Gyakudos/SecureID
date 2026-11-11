import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';

import '../util/ids.dart';
import 'device_key_store.dart';
import 'vault_crypto.dart';
import 'windows_dpapi.dart';

/// The device unlock record: the vault key wrapped with a key that only this
/// device can use (DPAPI on Windows, the Android Keystore on Android).
class PinVaultRecord {
  const PinVaultRecord({required this.vaultId, required this.wrappedKey});

  /// Base64 of the vault's KDF salt, used to bind this record to one vault.
  final String vaultId;

  /// AES-GCM nonce + ciphertext + MAC of the vault key.
  final List<int> wrappedKey;

  String encode() => jsonEncode({
    'format': 'secureid-pin',
    'version': 1,
    'vaultId': vaultId,
    'wrappedKey': base64Encode(wrappedKey),
  });

  factory PinVaultRecord.decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'secureid-pin' ||
        decoded['version'] != 1) {
      throw const FormatException('Not a SecureID device unlock record.');
    }
    final vaultId = decoded['vaultId'] as String? ?? '';
    final wrappedKey = base64Decode(decoded['wrappedKey'] as String? ?? '');
    if (vaultId.isEmpty ||
        wrappedKey.length < VaultCrypto.nonceLength + VaultCrypto.macLength) {
      throw const FormatException('The device unlock record is incomplete.');
    }
    return PinVaultRecord(vaultId: vaultId, wrappedKey: wrappedKey);
  }
}

/// Thrown when the user dismisses the platform unlock prompt.
class PinUnlockCancelled implements Exception {
  const PinUnlockCancelled();
}

/// Thrown when device unlock cannot finish. [message] is safe to show to the
/// user.
class PinUnlockException implements Exception {
  const PinUnlockException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Platform-specific unlock with a fingerprint, face, Windows Hello PIN or
/// Android biometric.
///
/// Implementations prompt the user themselves, so the caller never has to know
/// whether the prompt is bound to a Windows DPAPI key or an Android Keystore
/// operation.
abstract class PinUnlock {
  bool get isPlatformSupported;

  /// The name of the feature on this platform, for headings and messages.
  String get featureName;

  /// The label for the unlock button, e.g. "Unlock with Windows Hello".
  String get unlockButtonLabel;

  /// Help text shown when the feature is enabled.
  String get availableHint;

  /// Help text shown when the platform has no enrolled biometric or PIN.
  String get unavailableHint;

  Future<bool> isAvailable();

  /// Prompts the user, then wraps the vault key for this device.
  Future<PinVaultRecord> wrapVaultKey({
    required List<int> vaultKey,
    required List<int> salt,
  });

  /// Prompts the user, then unwraps the vault key.
  Future<List<int>> unwrapVaultKey(PinVaultRecord record);

  Future<void> clearDeviceKey();
}

/// Windows Hello / PIN unlock.
///
/// The vault key is sealed with a random 256-bit device key, and that device
/// key is kept in a DPAPI-sealed file that only the current Windows user can
/// open.
class PinUnlockService implements PinUnlock {
  PinUnlockService({LocalAuthentication? auth, DeviceKeyStore? deviceKeyStore})
    : _auth = auth ?? LocalAuthentication(),
      _deviceKeyStore = deviceKeyStore ?? WindowsDpapiDeviceKeyStore();

  final LocalAuthentication _auth;
  final DeviceKeyStore _deviceKeyStore;

  static const String _aad = 'secureid-pin-v1';
  static final AesGcm _cipher = AesGcm.with256bits();

  @override
  bool get isPlatformSupported => Platform.isWindows;

  @override
  String get featureName => 'Windows Hello';

  @override
  String get unlockButtonLabel => 'Unlock with Windows Hello';

  @override
  String get availableHint =>
      'Use your PIN, fingerprint or face to unwrap the vault key. Your master '
      'password always remains valid.';

  @override
  String get unavailableHint =>
      'Windows Hello is not set up on this PC. Add a PIN in Windows Settings '
      'first.';

  @override
  Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<void> _authenticateOrThrow() async {
    if (!isPlatformSupported) {
      throw const PinUnlockException(
        'Windows Hello unlock is only available on Windows.',
      );
    }
    final authenticated = await _authenticate();
    if (!authenticated) throw const PinUnlockCancelled();
  }

  Future<bool> _authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock SecureID',
        biometricOnly: false,
        sensitiveTransaction: false,
      );
    } catch (_) {
      return false;
    }
  }

  /// Returns the device key, creating and persisting one if this is the first
  /// time Windows Hello unlock is enabled.
  Future<Uint8List> _ensureDeviceKey() async {
    final existing = await _readDeviceKey();
    if (existing != null) return existing;
    final created = Uint8List.fromList(randomBytes(32));
    await _deviceKeyStore.write(created);
    return created;
  }

  /// Reads the existing device key. Returns null when none has been stored;
  /// this never silently creates a new key, because that would make an
  /// existing Windows Hello record permanently undecryptable.
  Future<Uint8List?> _readDeviceKey() async {
    try {
      final stored = await _deviceKeyStore.read();
      if (stored == null) return null;
      if (stored.length != 32) {
        throw const FormatException('The stored device key is invalid.');
      }
      return Uint8List.fromList(stored);
    } on WindowsDpapiException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearDeviceKey() => _deviceKeyStore.delete();

  @override
  Future<PinVaultRecord> wrapVaultKey({
    required List<int> vaultKey,
    required List<int> salt,
  }) async {
    await _authenticateOrThrow();
    final deviceKey = await _ensureDeviceKey();
    final box = await _cipher.encrypt(
      vaultKey,
      secretKey: SecretKey(deviceKey),
      aad: utf8.encode(_aad),
    );
    return PinVaultRecord(
      vaultId: base64Encode(salt),
      wrappedKey: box.concatenation(),
    );
  }

  @override
  Future<List<int>> unwrapVaultKey(PinVaultRecord record) async {
    await _authenticateOrThrow();
    final deviceKey = await _readDeviceKey();
    if (deviceKey == null) {
      throw const FormatException(
        'The device key for this Windows Hello record is missing.',
      );
    }
    final box = SecretBox.fromConcatenation(
      record.wrappedKey,
      nonceLength: VaultCrypto.nonceLength,
      macLength: VaultCrypto.macLength,
    );
    return _cipher.decrypt(
      box,
      secretKey: SecretKey(deviceKey),
      aad: utf8.encode(_aad),
    );
  }
}
